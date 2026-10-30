# Grabpic 0.7.0 for macOS

The first public macOS build: native SwiftUI and AppKit, with the purple camera identity and local-only capture workflow.

## Download

`Grabpic-0.7.0-macOS-arm64.zip` — Apple silicon, macOS 14 deployment target. Built and checked on macOS 26.6.2; older macOS runtime compatibility and Intel Macs have not been verified. Compare your download against `SHA256SUMS-macOS.txt` with `shasum -a 256`.

Unzip, move Grabpic.app to Applications, and open it. Grant Screen Recording permission, then relaunch. This app is ad-hoc signed and **not Developer ID signed or notarized**. Gatekeeper may block it; approving a trusted download in System Settings → Privacy & Security may be necessary. Microphone permission is requested only when microphone audio is enabled.

## Included

- Full-screen, pointer-display, all-display, and selected-area screenshots.
- PNG/JPG saving, automatic clipboard copy, daily/ISO-week/monthly folders, and latest-capture restoration.
- Screen and area recording to H.264/AAC MP4, system audio, optional microphone, 30/60 fps, and full-resolution/1080p options.
- Menu-bar capture without opening the main window; configurable keyboard shortcuts.
- Optional clipboard-image saving, capture flash, shutter sound, menu-bar visibility, and start at login.
- Dark interface, generated-content product screenshots, source, build scripts, and permission-free QA tools.

## Validation and limits

A fresh optimized arm64 build, signature verification, 54 permission-free logic checks, and seven real-view preview renders passed. Product images use generated content and disposable settings. Interactive recording/audio, permission revocation, area dragging, keyboard navigation, login behavior, physical multiple displays, and older macOS versions were not reverified for publication. Existing documentation records earlier capture checks separately; these are not a claim of full recording or hardware coverage.

Mac browser capture, mouse-button shortcuts, Finder integration, annotation, OCR, and cloud services are absent. No personal captures, preferences, signing credentials, or generated build directories are committed.

Windows remains available at [v0.6.0](https://github.com/talhazahid/grabpic/releases/tag/v0.6.0); its source and release workflow are preserved. See the [macOS documentation](https://github.com/talhazahid/grabpic/blob/main/macos/README.md) for details. GPL-3.0.
