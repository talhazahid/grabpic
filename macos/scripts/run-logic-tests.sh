#!/bin/bash
# Runs the permission-free logic checks against the real model, storage, and composer sources.
# These cover naming, folder organization, encoding, cropping orientation, multi-display
# composition, shortcut validation, and preference persistence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$ROOT/build"
BINARY="$BUILD/GrabpicLogicTests"
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
    if command -v xcrun >/dev/null 2>&1; then
        xcrun --find swiftc 2>/dev/null && return 0
    fi
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
    if command -v xcrun >/dev/null 2>&1; then
        xcrun --sdk macosx --show-sdk-path 2>/dev/null && return 0
    fi
    return 1
}

SWIFTC="$(find_toolchain)"
SDK="$(find_sdk)"
mkdir -p "$BUILD"

SOURCES=(
    "$ROOT/Grabpic/Model/CaptureAction.swift"
    "$ROOT/Grabpic/Model/Preferences.swift"
    "$ROOT/Grabpic/Model/ShortcutBinding.swift"
    "$ROOT/Grabpic/Storage/CaptureStore.swift"
    "$ROOT/Grabpic/Capture/DisplayShot.swift"
    "$ROOT/Grabpic/Capture/ImageComposer.swift"
    "$ROOT/QA/main.swift"
)

"$SWIFTC" -swift-version 5 -sdk "$SDK" -target "$TARGET" "${SOURCES[@]}" -o "$BINARY"

# Run from a scratch profile so the developer's real preferences are never touched.
export GRABPIC_PROFILE_DIRECTORY="$BUILD/logic-tests-profile"
rm -rf "$GRABPIC_PROFILE_DIRECTORY"

exec "$BINARY"
