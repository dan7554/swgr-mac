# Findings, in the order they were hit (2026-10-26)

Each entry: what was tried, what happened, the evidence, and the conclusion.

## 1. Apple's own GPTK Homebrew formula does not build
`apple/apple/game-porting-toolkit` was last updated November 2023. It pins a clang 8
toolchain and fails on Command Line Tools 16 and newer with "C compiler cannot create
executables". Apple's README's Option 1 (Gcenx's prebuilt cask) is the practical route.

## 2. Steam cannot run on the GPTK app's Wine 7.7
Steam's October 2026 client crashes at startup under `Game Porting Toolkit.app`
(Wine 7.7, CrossOver 22 base). Fault address lies inside Wine's own `bcrypt.dll`
(loaded at 0x2D4D40000): the client calls a crypto API that Wine never implemented.
Independent of D3DMetal version. The toolkit's Wine is dead for Steam.

## 3. GPTK 4.0b3 facts
- `Game_Porting_Toolkit_4.0_beta_3.dmg` contains an inner
  `Evaluation environment for Windows games 4.0 beta 3.dmg` with `redist/lib/{external,wine}`.
- D3DMetal reports version `4.0b3`. Runs on macOS 15 and later; the Metal 4 backend is
  default only on macOS 27 (`D3DM_MTL4`).
- The redist's `wine/` folder holds only 7 DLLs plus 7 `.so` symlinks. Apple's README says
  to move the whole `wine` folder aside before copying; in the Gcenx app that folder is the
  entire Wine DLL set, so **merge, do not replace**.
- New in 4.0: `d3d12core.dll` (Agility SDK games), `nvngx-on-metalfx` (DLSS to MetalFX,
  including DLSS-G to MetalFX frame interpolation: the framework contains
  `MDEFrameInterpolator` and all `DLSSG.*` inputs).
- CrossOver 26.3 ships D3DMetal 3.0, byte-identical to the Gcenx bundle's.

## 4. macOS App Management blocks writes into CrossOver.app
Copying into `CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk` returns
"Operation not permitted" (developer-signed, quarantined bundle). Granting the terminal
app App Management in System Settings fixes it. The ad-hoc-signed GPTK app is not protected.

## 5. The game's Denuvo build cannot run on stock CrossOver (or any stock Wine) under Rosetta
Trace (`WINEDEBUG=+seh,+loaddll`): Denuvo probes `serialize`, `clwb`, `rdpid` (expected
illegal-instruction faults, absorbed by its handler), then calls `NtSetContextThread`
to arm debug registers. CrossOver logs
`Setting debug registers is not supported under Rosetta, faking success`. Denuvo then
derails into access violations at non-canonical pointers that its own handler refuses,
and the process either fast-fails (exit 0xC0000409, via Steam) or spins in an unwind
loop (direct launch). `ROSETTA_ADVERTISE_AVX=1` changes nothing. Rosetta's CPUID does not
advertise CLWB/RDPID/SERIALIZE, so the probes themselves are consistent; the debug
registers are the blocker. Confirmed by NotProton issue #113 and a CodeWeavers report.

## 6. Hrava's engine has the missing pieces
`~/Library/Application Support/GreatGame/Engines/winecx-26.2-custom-v15` (left behind after
removing Hrava) carries, with GPL source offer in `share/hrava/Legal`:
- `26.2-ntdll-rosetta-cpu-fidelity.patch`: software emulation of hardware execution
  breakpoints (guarded pages + single-step), CPUID leaf-7 extension via
  `WINE_ROSETTA_CPUID7_OR=<ebx>,<ecx>` (e.g. `01800000,00400000` = CLFLUSHOPT+CLWB, RDPID),
  and emulation of `clwb`/`rdpid`.
- `26.2-ntdll-rosetta-far32-return.patch`: precise invalid-opcode faults, far returns into
  32-bit mode (for NCGuard-style probes).
- `26.2-ntdll-per-exe-graphics-directory.patch`: `HKCU\Software\Wine\AppDefaults\<exe>\Direct3D`
  `GraphicsDllDirectory64` redirects dxgi/d3d10core/d3d11/d3d12/d3d12core loads.
With this engine and those env vars the game passes Denuvo, opens its paks and runs.

## 7. Getting Apple's DLLs loaded by that engine: three attempts
1. `WINEDLLPATH` with the Apple set first: **ignored**. Wine builds its DLL search list with
   its own `lib/wine` first and only appends `WINEDLLPATH`.
2. Hrava's per-exe registry redirect: loads the PE from the redirected path, **but** since
   the file is a Wine builtin, `find_builtin_dll` re-resolves it by name and maps the
   engine's own `d3d12.dll`/`dxgi.dll` (vkd3d / wined3d) under Apple's name. Result: UE's
   "DirectX 12 is not supported on your system" dialog (hidden, found with
   `winedbg --command "info wnd"` and `WINEDEBUG=+edit,+dialog`).
3. Install Apple's DLLs into the engine's `lib/wine/x86_64-windows`, `.so` symlinks in
   `x86_64-unix` to `../../external/libd3dshared.dylib`, framework in `lib/external`:
   **works**. `scripts/stage-gptk-into-engine.sh` does this with backups.

Also needed: the Hrava bottle has no `Z:` drive (its `z:` points inside the prefix), so
Windows paths to the home directory do not resolve there.

## 8. Colors: UE5's 10-bit swap chain is presented far too bright
HDR was already off in the game's settings. The fix is
`r.DefaultBackBufferPixelFormat=0` (8-bit sRGB) plus the `r.HDR.*`/`r.AllowHDR` cvars in
the user `Engine.ini` (`Saved/Config/Windows/Engine.ini`). The game deletes that file on
some launches, so it is locked with `chflags uchg` and the launcher restores it from
`config/Engine.ini` when missing. Ray tracing and the Metal 4 backend were not involved.

## 9. Steam launch flow
- Launching the executable directly with `steam_appid.txt` beside it works and Steam still
  tracks playtime and provides Steamworks.
- Steam's own launch (`steam.exe -applaunch 4078430`) runs the update check, install
  scripts, cloud and stats sync, then the EOS bootstrapper (`Launcher.exe`),
  `SWGR.exe` (BootstrapPackagedGame) and the shipping exe. The EOS host service exits with
  code 7 under Wine but the chain continued in the CrossOver tests. A stalled Steam UI
  silently drops launch requests (no `GameAction` lines in `logs/console_log.txt`);
  restarting Steam fixes it. Steam may pause on a "Steam Dialog" interstitial that needs a click.
- `--dock` mode: Steam flow first (90 s), direct launch after the scheduler reports
  `StateFlags 4` as fallback.

## 10. Performance
GPU-bound (device utilization 84 to 96 percent). CPU: no Unreal thread saturated; most
CPU time is Rosetta JIT re-translation caused by Denuvo's virtualized code. FSR 3 frame
interpolation gave the big improvement; hardware ray tracing on/off did little. The
`sample`-based profiler at 1 ms interval tanks the game; 25 ms is nearly free.
The game rewrites `GameUserSettings.ini` from its internal preset on exit, so quality
changes must be made in the in-game menu.

## Environment variables used by the launcher
`ROSETTA_ADVERTISE_AVX=1`, `WINE_ROSETTA_CPUID7_OR=01800000,00400000`, `WINEMSYNC=1`,
`CX_GRAPHICS_BACKEND=d3dmetal`, `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`,
`CX_APPLEGPTK_LIBD3DSHARED_PATH`, `D3DMETAL_FRAMEWORK_PATH`, `MTL_HUD_ENABLED`,
optional `D3DM_SUPPORT_DXR`, `D3DM_MTL4`, `D3DM_ENABLE_METALFX`, `D3DM_VENDOR_ID`,
`D3DM_DEVICE_ID`, `D3DM_DEVICE_DESCRIPTION`, `D3DM_SHOW_HUD_STATS`, `D3DM_MAX_FPS`.

## 11. Dock launches felt slower: two causes found
- Steam's first launch attempt ran the game's install script, which installed **Epic Online
  Services** into the prefix. From then on the EOS SDK injected four `EOSOverlayRenderer`
  processes (a Chromium overlay) into the game. The SDK finds the overlay through
  `HKLM\Software\Wow6432Node\Epic Games\EOS\OverlayPath`; `scripts/eos-overlay.sh off`
  removes that value (reversible with `on`).
- The settings file had flipped from exclusive fullscreen (0) to windowed fullscreen (1),
  which goes through the compositor. Set it back in the game's display menu.
- Precaution: the Dock app now has `NSAppSleepDisabled` and runs the launcher through
  `taskpolicy -t 0 -l 0`, so App Nap cannot push the Wine processes into a background
  scheduling class.

## 12. Upscaling and frame generation: what is stable
- **FSR 3 upscaling alone (frame interpolation off): stable, no flicker.** This is the setting
  to use. Combined with TSR off it is where the good frame rate came from.
- FSR 3 frame interpolation: flickers on D3DMetal 4.0b3 even with
  `r.FidelityFX.FI.AllowAsyncWorkloads=0` (kept in Engine.ini, harmless when FI is off).
- Untested alternative for frame generation: `swgr-run --metalfx` with DLSS Frame Generation
  selected in the menu (D3DMetal maps it to MetalFX frame interpolation).

## 13. Performance, round two (2026-11-03): what is left to pull

Hardware context: MacBook Air (Mac17,3), Apple M5, 10 GPU cores, 32 GB, 2560x1664 panel at a
1470x956 logical desktop (Wine Retina mode off, so the game outputs 1470x956 and the compositor
scales it). Fanless, so sustained GPU load throttles; it was also on battery during the profile.

What the saved settings say: Medium preset, FSR 3 upscaling in **Ultra Performance** (1/3 render
resolution, roughly 490x318 internal) with `sg.ResolutionQuality=75`, frame interpolation off,
hardware RT on, 60 fps cap, exclusive fullscreen. Even at that render resolution the GPU sat at
84 to 96 percent, so the remaining cost is in passes that do not scale with the upscaler's
render resolution: virtual shadow map pages, Nanite cluster raster, volumetric fog/cloud froxels,
distance-field and screen-space extras, and the post chain plus the FSR upscale pass at output
resolution. CPU is already around 450 to 550 percent (Rosetta translation of Denuvo-virtualised
code); no single Unreal thread is pegged.

Levers added to the launcher (untested until the next play session):
- `--perf`: Engine.ini profile that biases VSM page resolution down by 1 LOD, halves Nanite
  raster density (`r.Nanite.MaxPixelsPerEdge=2`), turns off volumetric fog/cloud, SSR,
  distance-field shadows/AO, Lumen reflections, DOF, lens flares, light shafts. Keeps the look
  mostly intact.
- `--perf-max`: the same plus `r.Shadow.Virtual.Enable=0` (cascaded shadow maps at 1024,
  2 cascades). Biggest fixed-cost saving; shadows get softer and shorter-range.
- `--metalfx`: D3DMetal 4's DLSS-to-MetalFX mapping. Verified the plumbing: the engine's
  `nvngx.dll` is byte-identical to Apple's `nvngx-on-metalfx.dll`, `nvngx.so` points at
  libd3dshared, and the prefix's system32 copies are Wine placeholders that forward to it, which
  is what Apple's Read Me asks for. The game ships both the DLSS plugin (`nvngx_dlss.dll`) and
  Streamline (`sl.dlss_g.dll`), so the menu should offer DLSS Super Resolution and DLSS Frame
  Generation when the launcher spoofs an NVIDIA adapter. MetalFX temporal upscaling at
  Performance (50 percent) should look better than FSR Ultra Performance at a similar cost, and
  MetalFX frame interpolation is the only frame-generation path that does not flicker in FSR's
  way (FSR FI did; see section 12).
- `--lod-bias=N` (D3DM_LOD_BIAS) and `--max-fps=N` (D3DM_MAX_FPS) for bandwidth and thermal
  experiments.

Test ladder (run from a terminal so the Metal HUD shows; read FPS and GPU time on the same track
segment each time; keep the laptop plugged in):
1. `swgr-run` as is: baseline number.
2. `swgr-run --perf`, then `--perf-max`: fixed-cost reductions. If `--perf-max` helps a lot and
   `--perf` does not, VSM was the cost.
3. `swgr-run --metalfx`: in the display menu pick DLSS for upscaling, Performance mode, then try
   DLSS Frame Generation. Compare with FSR Ultra Performance. If the DLSS entries do not appear,
   the vendor spoof did not take; `--d3dm-log` and look for NGX lines.
4. `swgr-run --mtl4`: Metal 4 backend (opt-in on macOS 26). Separate run; it changes the D3D12
   translation path, so compare against step 1.
5. If still GPU-bound: lower the output resolution in the game (1280x832 keeps the panel aspect)
   because post-processing and the upscale pass run at output resolution.

Things that will not help: `sg.ResolutionQuality`/FSR mode below Ultra Performance (already at
the floor), more CPU cores (WINE_CPU_TOPOLOGY already exposes all 10), ray tracing off (measured
earlier, little change).

## 14. Metal 4 backend is the default; chasing the once-or-twice-a-race stall (2026-11-03)
`--mtl4` was the best-feeling run, so the launcher now exports `D3DM_MTL4=1` by default (Dock
included); `--mtl3` goes back. Two stalls per race were reported with it. Evidence gathered:
- D3DMetal's shader cache for the game (`$(getconf DARWIN_USER_CACHE_DIR)/d3dm/SWGR-Win64-Shipping.exe`,
  1.1 GB) was still growing during the session: `stage_cache.bin`, `bytecode_cache.bin` and
  `functions.data` all changed minutes before exit. So shaders were still being compiled on first use
  mid-race. This decays over sessions as the cache fills; the Metal 4 backend started with a colder
  cache than Metal 3 had.
- The launch log shows `AGX: exceeded compiled variants footprint limit` from the GPU driver. No
  public knob for it exists (checked the driver binary), so the driver may evict and recompile
  variants. Nothing to do but keep the cache warm and reduce variant count (lower quality presets
  help here too).
- Unreal's garbage collector purges on a timer (about every 61 s by default), which lines up with
  "twice in a race". Mitigation added to every Engine.ini profile: incremental reachability and
  gather, purge interval raised to 600 s, multithreaded destruction, no forced GC after a streamed
  level unloads. Also PSO precaching with larger startup batches.
- Memory: the Mac has 32 GB of unified memory and the game sat at about 5 GB resident, so the
  streaming pools are now sized for that instead of for a small discrete card: texture pool 8 GB
  (decoupled from the VRAM figure D3DMetal reports), 1 GB of temp streaming memory per frame,
  Nanite streaming pool 2 GB, virtual-texture pools doubled. Fewer mip and page re-streams means
  fewer stalls; expect resident memory to grow by a few GB.
- The launcher now remembers the chosen profile in `~/.config/swgr/profile` and re-syncs the
  locked Engine.ini from the template on every launch, so edits to `config/*.ini` reach the game
  without passing a flag again.
- One PSO fails to build on Metal 4 (`texcoord14` vertex/fragment mismatch) and is marked no-op; a
  rendering bug to report, not a stall.
If the stalls persist after two or three sessions, run `swgr-run --d3dm-log` and send the log: the
timestamps of new `[D3DMetal:LOG` lines versus the stalls will tell compile hitches from GC.

## 15. Only the top-left of the game visible (2026-11-03)
Symptom: the frame filled the screen but its bottom-right was off-screen. Cause: the macOS
Displays scaling had been changed to "More Space" (1710x1112 logical, 3420x2224 backing) while
the game was still saved at 1470x956 exclusive fullscreen, the size of the desktop on 2026-10-26.
Wine runs this bottle with Retina mode off, so Windows sees the logical desktop size, and Wine never
switched the panel's mode for the game (no `Initial Display Mode` key was ever written). The
launcher now reads the main screen size through AppKit (`osascript -l JavaScript`, no automation
permission needed) and rewrites `ResolutionSizeX/Y`, `DesiredScreenWidth/Height` and their
`LastUserConfirmed*` twins in `GameUserSettings.ini` when they differ, before every launch.
`--keep-res` skips it. Output resolution follows the desktop, so "More Space" costs about 35
percent more pixels in the output-resolution passes than the Default scaling; set the Displays
scaling back to Default (1470x956) for the cheapest full-screen output.

