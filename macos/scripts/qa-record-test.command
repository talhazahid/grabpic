#!/bin/bash
# QA: builds, quits Grab Pic, launches the fresh build to record 6 s of the screen, and collects
# the menu bar item log into build/record-test.log. Reopens Grab Pic afterwards.
cd "$(dirname "$0")/.." || exit 1
OUT="$PWD/build/record-test.log"
echo "started $(date)" > "$OUT"
if [[ "$1" != "--no-build" ]]; then
  ./scripts/build.sh >> "$OUT" 2>&1 || { echo "BUILD FAILED" >> "$OUT"; exit 1; }
  rm -rf "$HOME/Downloads/Grabpic.app"; ditto build/Grabpic.app "$HOME/Downloads/Grabpic.app"
fi
LOG_SRC="$HOME/Library/Application Support/Grabpic/recording-debug.log"
rm -f "$LOG_SRC"
pkill -x Grabpic; sleep 1.5
open -n build/Grabpic.app --args --record-test
sleep 18
{ echo "== log"; ls -la "$LOG_SRC" 2>&1; cat "$LOG_SRC" 2>&1; cp "$LOG_SRC" build/recording-debug.log 2>&1; echo "== defaults"; defaults read com.owl.grabpic 2>&1 | grep -i "statusitem\|position\|placed"; echo "== settings"; grep -i "menuBar\|record" "$HOME/Library/Application Support/Grabpic/settings.json" 2>&1; echo "DONE"; } >> "$OUT"
