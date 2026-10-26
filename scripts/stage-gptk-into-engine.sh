#!/bin/zsh
# Put Apple's Game Porting Toolkit evaluation-environment libraries (D3DMetal + the
# DirectX bridge DLLs) into the Rosetta-patched Wine engine so they become the engine's
# builtin d3d10/d3d11/d3d12/d3d12core/dxgi (plus nvapi64/nvngx/atidxx64 stubs).
#
# Source precedence: argument > mounted "Evaluation environment for Windows games" DMG
#                    > CrossOver's lib64/apple_gptk > Game Porting Toolkit.app
# Why the engine tree: Wine searches its own lib/wine first, so WINEDLLPATH cannot
# override builtins, and a per-exe registry redirect only renames the request.
set -e
E="${ENGINE:-$HOME/Library/Application Support/GreatGame/Engines/winecx-26.2-custom-v15}"
SRC="${1:-}"
if [ -z "$SRC" ]; then
  V=$(ls -d /Volumes/Evaluation\ environment* 2>/dev/null | sort | tail -1)
  if [ -n "$V" ] && [ -d "$V/redist/lib" ]; then SRC="$V/redist/lib"
  elif [ -d /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk ]; then SRC=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk
  elif [ -d "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib" ]; then SRC="/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib"
  fi
fi
[ -d "$SRC/external" ] && [ -d "$SRC/wine/x86_64-windows" ] || { echo "no GPTK library set found; pass a path containing external/ and wine/x86_64-windows/" >&2; exit 1; }
[ -d "$E/lib/wine/x86_64-windows" ] || { echo "engine not found at $E" >&2; exit 1; }
W="$E/lib/wine/x86_64-windows"; U="$E/lib/wine/x86_64-unix"; BK="$E/lib/wine/pre-gptk-backup"
echo "source: $SRC  ->  engine: $E"
mkdir -p "$BK/x86_64-windows" "$BK/x86_64-unix"
for f in d3d10 d3d11 d3d12 d3d12core dxgi nvapi64 nvngx atidxx64; do
  [ -e "$SRC/wine/x86_64-windows/$f.dll" ] || [ -e "$SRC/wine/x86_64-windows/nvngx-on-metalfx.dll" ] || continue
  [ -e "$W/$f.dll" ] && [ ! -e "$BK/x86_64-windows/$f.dll" ] && cp -p "$W/$f.dll" "$BK/x86_64-windows/$f.dll"
  [ -e "$U/$f.so" ] && [ ! -e "$BK/x86_64-unix/$f.so" ] && cp -Rp "$U/$f.so" "$BK/x86_64-unix/$f.so"
  if [ "$f" = nvngx ] && [ ! -e "$SRC/wine/x86_64-windows/nvngx.dll" ]; then cp -f "$SRC/wine/x86_64-windows/nvngx-on-metalfx.dll" "$W/nvngx.dll"
  elif [ -e "$SRC/wine/x86_64-windows/$f.dll" ]; then cp -f "$SRC/wine/x86_64-windows/$f.dll" "$W/$f.dll"; else continue; fi
  ln -sfn ../../external/libd3dshared.dylib "$U/$f.so"
done
rm -rf "$E/lib/external.new"; cp -R "$SRC/external" "$E/lib/external.new"
[ -d "$E/lib/external" ] && { rm -rf "$E/lib/external.old"; mv "$E/lib/external" "$E/lib/external.old"; }
mv "$E/lib/external.new" "$E/lib/external"
echo "installed D3DMetal $(defaults read "$E/lib/external/D3DMetal.framework/Versions/A/Resources/Info.plist" CFBundleShortVersionString)"
echo "engine originals backed up in $BK"
