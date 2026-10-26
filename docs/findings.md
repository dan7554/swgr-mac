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
