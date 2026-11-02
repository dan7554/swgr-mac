# swgr-mac

Running **STAR WARS: Galactic Racer** (Steam app 4078430) on an Apple Silicon Mac with
Apple's **Game Porting Toolkit 4.0 beta 3** (D3DMetal), without the Hrava app.

Everything here was worked out on 2026-10-26 on a MacBook with an M5, macOS 26.6.2.
The game runs at a playable frame rate with FSR 3 frame interpolation, correct colors,
Steam logged in, and a Dock icon. See [docs/findings.md](docs/findings.md) for every
dead end and why it was a dead end.

## The working stack

| Layer | What is used | Why |
|---|---|---|
| Wine | Hrava's leftover engine `winecx-26.2-custom-v15` (CrossOver 26.2 base, GPL, with Hrava's Rosetta patches) | The game's Denuvo build arms x86 **hardware debug registers**, which Rosetta cannot provide. This engine emulates execution breakpoints in software, extends CPUID leaf 7 and emulates `clwb`/`rdpid`. Stock CrossOver 26.3 and Apple's own Wine 7.7 both fail. |
| Graphics | Apple D3DMetal 4.0b3 from the GPTK DMG, installed **into the engine's `lib/wine`** | Wine always searches its own library folder first, so this is the only placement that makes Apple's DLLs win. |
| Prefix | Hrava's `Games` bottle (`~/Library/Application Support/GreatGame/Bottles/Games`) | Steam is logged in there and the 39 GB install lives there. |
| Launch | `swgr-run` starts Steam if needed, then the game executable directly with `steam_appid.txt` | The Epic Online Services bootstrapper chain is unreliable under Wine. Dock mode tries Steam's own flow first (update check), then falls back. |
| Colors | `config/Engine.ini` (locked, self-restoring) forcing an 8-bit sRGB swap chain and HDR off | UE5's default 10-bit swap chain is presented far too bright by D3DMetal. |

## Install

```sh
git clone <this repo> ~/code/swgr-mac
~/code/swgr-mac/scripts/install.sh          # links bin/* into ~/bin, copies the Dock app
~/code/swgr-mac/scripts/stage-gptk-into-engine.sh   # Apple libs into the engine (needs the DMG, CrossOver or the GPTK app)
~/bin/swgr-run                              # play
```

Apple's libraries are **not** in this repo (their license forbids redistribution). The
staging script takes them from a mounted "Evaluation environment for Windows games" DMG,
from `/Applications/CrossOver.app`, or from the Gcenx `Game Porting Toolkit.app`.

## Day-to-day

```
~/bin/swgr-run              Steam if needed, then the game (Metal HUD on)
~/bin/swgr-run --no-hud     hide the HUD
~/bin/swgr-run --dock       what the Dock icon runs: Steam launch flow with update check, direct fallback, HUD off
~/bin/swgr-run --metalfx    expose DLSS options and map them to MetalFX upscaling / frame interpolation (experimental)
~/bin/swgr-run --mtl4       force D3DMetal's Metal 4 backend (default only on macOS 27)
~/bin/swgr-run --no-rt      hide DirectX Raytracing from the game
~/bin/swgr-run --stats      HUD with D3DMetal's extra counters
~/bin/swgr-run --d3dm-log   keep output in ~/swgr-last.log
~/bin/swgr-run steam        only Steam
~/bin/swgr-profile 60       low-overhead profile while racing (GPU %, busy threads, hot libraries)
~/bin/swgr-analyze FILE     re-analyze a saved `sample` file
```

Dock: drag `~/Applications/Galactic Racer.app` to the Dock. Its log is
`~/Library/Logs/galactic-racer-launch.log`.

## Performance notes (M5, 2560x1664 display)

Profiled with `swgr-profile`: GPU device utilization 84 to 96 percent during a race, no
Unreal thread pegged, and 84 percent of the CPU time that does exist is Rosetta's JIT
re-translating code (Denuvo's virtualized code defeats ahead-of-time translation). The
game is GPU-bound. Ray tracing on or off made little difference; FSR 3 frame interpolation
made the difference. Quality settings only stick when changed in the game's own menu: the
game regenerates `GameUserSettings.ini` from its internal preset on exit.

## Layout

```
bin/      launchers, profiler, library installers (also the historical CrossOver/GPTK-app ones)
config/   Engine.ini override (the launcher restores it if the game deletes it)
dock/     the Dock app bundle and its icon (icon extracted from Steam's cache)
scripts/  install.sh, stage-gptk-into-engine.sh
docs/     findings.md (everything that failed and why), a raw profile
```

## Credits

Hrava's engine patches (`26.2-ntdll-rosetta-cpu-fidelity.patch`,
`26.2-ntdll-rosetta-far32-return.patch`, per-exe graphics directory, msync) are what
make this game run on Rosetta at all; the engine ships its GPL source offer under
`share/hrava/Legal`. Apple's README in the GPTK DMG documents the environment variables
(`D3DM_*`, `ROSETTA_ADVERTISE_AVX`, `MTL_HUD_ENABLED`).
