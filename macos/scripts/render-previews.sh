#!/bin/bash
# Builds and runs the QA preview renderer. It compiles the real UI sources (without the app
# entry point) and renders generated content, so no screen-recording permission is involved.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$ROOT/build/previews"
TARGET="${TARGET:-arm64-apple-macos14.0}"

find_toolchain() {
    local candidates=(
        "${SWIFTC:-}"
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        "/Library/Developer/CommandLineTools/usr/bin/swiftc"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_sdk() {
    local candidates=(
        "${SDKROOT:-}"
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

SWIFTC="$(find_toolchain)"
SDK="$(find_sdk)"
mkdir -p "$BUILD"

SOURCES=()
while IFS= read -r -d '' source; do
    SOURCES+=("$source")
done < <(find "$ROOT/Grabpic" -name '*.swift' ! -name 'GrabpicApp.swift' -print0 | sort -z)
SOURCES+=("$ROOT/QA/PreviewRenderer.swift")

"$SWIFTC" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -sdk "$SDK" \
    -target "$TARGET" \
    "${SOURCES[@]}" \
    -o "$BUILD/PreviewRenderer"

"$BUILD/PreviewRenderer" "$BUILD"
