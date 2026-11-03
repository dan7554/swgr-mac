#!/bin/zsh
# Install the launcher scripts into ~/bin and the Dock app into ~/Applications.
# Safe to re-run. Does not touch Wine, Steam, the game, or Apple's libraries
# (see scripts/stage-gptk-into-engine.sh for those).
set -e
HERE="${0:A:h}/.."
mkdir -p ~/bin ~/Applications
for f in "$HERE"/bin/*; do ln -sfn "$f" ~/bin/"$(basename "$f")"; done
ln -sfn "$HERE/config/Engine.ini" ~/bin/swgr-engine.ini.template
ln -sfn "$HERE/config/Engine.perf.ini" ~/bin/swgr-engine.perf.ini.template
ln -sfn "$HERE/config/Engine.perfmax.ini" ~/bin/swgr-engine.perfmax.ini.template
rm -rf ~/Applications/"Galactic Racer.app"
cp -R "$HERE/dock/Galactic Racer.app" ~/Applications/
touch ~/Applications/"Galactic Racer.app"
echo "installed: $(ls ~/bin | grep -E '^(swgr|steam|gptk)' | tr '\n' ' ')"
echo "Dock app: ~/Applications/Galactic Racer.app (drag it to the Dock)"
