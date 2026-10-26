#!/bin/zsh
# Turn the Epic Online Services overlay off or on for the Games prefix.
# The EOS SDK finds its overlay through HKLM\Software\Wow6432Node\Epic Games\EOS\OverlayPath;
# with the value removed, no EOSOverlayRenderer processes get injected into the game.
#   eos-overlay.sh off | on
E="$HOME/Library/Application Support/GreatGame/Engines/winecx-26.2-custom-v15"
export WINEPREFIX="$HOME/Library/Application Support/GreatGame/Bottles/Games" WINEDEBUG=-all WINEMSYNC=1
OVL='C:\\Program Files (x86)\\Epic Games\\Epic Online Services\\managedArtifacts\\98bc04bc842e4906993fd6d6644ffb8d'
F=$(mktemp /tmp/eos-overlay.XXXXXX.reg)
case "${1:-}" in
  off) printf 'Windows Registry Editor Version 5.00\r\n\r\n[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Epic Games\\EOS]\r\n"OverlayPath"=-\r\n' > "$F" ;;
  on)  printf 'Windows Registry Editor Version 5.00\r\n\r\n[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Epic Games\\EOS]\r\n"OverlayPath"="%s"\r\n' "$OVL" > "$F" ;;
  *) echo "usage: $0 off|on" >&2; exit 2 ;;
esac
cd /tmp && "$E/bin/wine" regedit.exe /S "$F" 2>/dev/null; rm -f "$F"
"$E/bin/wine" reg.exe query 'HKLM\Software\Wow6432Node\Epic Games\EOS' /v OverlayPath 2>/dev/null | grep -i OverlayPath || echo "OverlayPath: (not set) -> overlay off"
