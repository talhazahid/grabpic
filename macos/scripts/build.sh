#!/bin/bash
# Builds a launchable Apple-silicon Grabpic.app without requiring an Xcode project.
# Works with the Xcode toolchain directly, which also avoids the /usr/bin shim license gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Grabpic.app"
TARGET="${TARGET:-arm64-apple-macos14.0}"
SIGN_IDENTITY="${GRABPIC_SIGN_IDENTITY:--}"

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

SWIFTC="$(find_toolchain)" || {
    echo "error: no working Swift compiler found. Install Xcode 15 or later." >&2
    exit 1
}
SDK="$(find_sdk)" || {
    echo "error: no macOS SDK found. Set SDKROOT to a MacOSX.sdk path." >&2
    exit 1
}

if [[ ! -d "$SDK" ]]; then
    echo "error: SDK not found at $SDK" >&2
    exit 1
fi

echo "Toolchain  $SWIFTC"
echo "SDK        $SDK"
echo "Target     $TARGET"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The app icon is generated from the shared camera geometry, not renamed from the Windows ICO.
if [[ ! -f "$ROOT/Resources/Grabpic.icns" || "$ROOT/scripts/MakeIcon.swift" -nt "$ROOT/Resources/Grabpic.icns" ]]; then
    echo "Generating icon"
    "$SWIFTC" -swift-version 5 -sdk "$SDK" -target "$TARGET" "$ROOT/scripts/MakeIcon.swift" -o "$BUILD/MakeIcon"
    "$BUILD/MakeIcon" "$ROOT/Resources"
fi
cp "$ROOT/Resources/Grabpic.icns" "$APP/Contents/Resources/Grabpic.icns"

if [[ -f "$ROOT/../LICENSE" ]]; then
    cp "$ROOT/../LICENSE" "$APP/Contents/Resources/LICENSE"
fi

SOURCES=()
while IFS= read -r -d '' source; do
    SOURCES+=("$source")
done < <(find "$ROOT/Grabpic" -name '*.swift' -print0 | sort -z)

echo "Compiling ${#SOURCES[@]} Swift files"
"$SWIFTC" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -sdk "$SDK" \
    -target "$TARGET" \
    "${SOURCES[@]}" \
    -o "$APP/Contents/MacOS/Grabpic"

if command -v codesign >/dev/null 2>&1; then
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || echo com.owl.grabpic)"
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        # An ad-hoc signature's default requirement is its cdhash, which changes on every build,
        # so macOS forgets the Screen Recording approval each time (the switch stays on, but
        # captures fail). Pin the designated requirement to the bundle identifier instead so one
        # approval survives rebuilds.
        codesign --force --deep --sign - \
            --identifier "$BUNDLE_ID" \
            --requirements "=designated => identifier \"$BUNDLE_ID\"" \
            "$APP" || echo "warning: ad-hoc signing failed; the local build still runs." >&2
    else
        codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP" || \
            echo "warning: signing with $SIGN_IDENTITY failed." >&2
    fi
    codesign -d -r- "$APP" 2>&1 | grep -i designated || true
fi

echo "Built $APP"
echo "Open with: open \"$APP\""
echo "Background/QA launch: \"$APP/Contents/MacOS/Grabpic\" --background"
