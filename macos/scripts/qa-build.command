#!/bin/bash
# Builds Grab Pic and runs the logic tests and preview renderer. Output goes to build/qa.log.
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
LOG="$PWD/build/qa.log"
echo "started $(date)" > "$LOG"
{
  sw_vers; uname -m
  echo "== build"; ./scripts/build.sh; BUILD_STATUS=$?; echo "build exit $BUILD_STATUS"
  if [[ $BUILD_STATUS -eq 0 && -x build/Grabpic.app/Contents/MacOS/Grabpic ]]; then
    rm -rf "$HOME/Downloads/Grabpic.app"
    ditto build/Grabpic.app "$HOME/Downloads/Grabpic.app" && echo "copied to ~/Downloads/Grabpic.app"
  fi
  echo "== logic tests"; ./scripts/run-logic-tests.sh 2>&1 | tail -15; echo "tests exit ${PIPESTATUS[0]}"
  echo "== previews"; ./scripts/render-previews.sh 2>&1 | tail -15; echo "previews exit ${PIPESTATUS[0]}"
  echo "== codesign"; codesign -d -r- build/Grabpic.app 2>&1
  echo "DONE"
} >> "$LOG" 2>&1
