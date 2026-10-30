#!/bin/bash
# Build and package an ad-hoc-signed Apple silicon release; never includes local captures/settings.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"
"$ROOT/scripts/run-logic-tests.sh"
APP="$ROOT/build/Grabpic.app"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="$ROOT/build/release"
mkdir -p "$OUT"
NAME="Grabpic-$VERSION-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME"
(cd "$OUT" && shasum -a 256 "$NAME" > SHA256SUMS-macOS.txt)
echo "Release archive: $OUT/$NAME"
