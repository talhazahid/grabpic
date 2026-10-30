# Grabpic: start here

This repository contains the complete Grabpic Windows 0.6.0 application, companion browser-extension source, native Windows shell integration, icons, website, packaging scripts, and QA tools. The owner wants to use this source as the reference for a native macOS port.

A native macOS implementation now lives in `macos/` (version 0.7.0). Read [macos/README.md](macos/README.md) for build instructions, verified behavior, and limits. Windows remains version 0.6.0. WPF and Windows packaging remain Windows-specific.

## Read in this order

1. [AGENTS.md](AGENTS.md): owner preferences and repository rules.
2. [README.md](README.md): product overview, Windows build commands, screenshots.
3. [DESIGN.md](DESIGN.md): existing design tokens and hierarchy.
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): source map, flows, settings schema, browser protocol, and known limits.
5. [docs/MACOS-PORT.md](docs/MACOS-PORT.md): proposed macOS implementation, permissions, parity checklist, and acceptance tests.
6. [docs/BROWSERS.md](docs/BROWSERS.md), [docs/PRIVACY.md](docs/PRIVACY.md), [docs/RELEASE-0.6.0.md](docs/RELEASE-0.6.0.md): browser setup, privacy, verified and unverified behavior.

Then inspect the actual C# and JavaScript files named by those documents; source code is authoritative if it differs from a description. The handoff baseline is tag [v0.6.0](https://github.com/talhazahid/grabpic/tree/v0.6.0), commit `db8fcdd4767bbd6cc90364253634c1f39609b536`. Later documentation commits do not change that binary version.

## Product rules that matter most

- A small screenshot utility with a polished, consistent dark interface. No 600/700 typography; use regular weight and a size hierarchy.
- Capture the monitor under the pointer, all visible displays, or a user-selected area. Hidden virtual desktops/Spaces are not a capture source.
- Save locally and copy to the clipboard by default. PNG is the default; JPG quality defaults to 100. Quality 100 does not make JPEG lossless.
- User-chosen folder; daily, ISO weekly, or monthly grouping; collision-resistant filenames.
- Run in the tray on Windows / menu bar on macOS. Closing the settings window keeps the app running. Captures never reopen the main window.
- Explicitly opening the app restores the latest saved image, including after restart.
- Three configurable action bindings: full screen, area, open captures. Validate duplicates, reserved keys, conflicts, and mouse bindings.
- Optional clipboard-image saving is off by default and must not repeatedly save the app's own clipboard writes.
- Optional browser actions distinguish full scrolling page, visible webpage viewport, and native screen-area selection. The extension is separately enabled by the user.
- No account, remote screenshot upload, advertising, analytics, or typing-history collection.

## Port implementation expectations

Use a native macOS approach (SwiftUI with AppKit/ScreenCaptureKit adapters is the proposed direction). Add it under `macos/` without replacing the working Windows implementation. Reuse the browser JavaScript, source artwork, behavior, and test cases where appropriate; replace the Windows native bridge and installer.

Do not promise an identical Windows desktop context menu in Finder, silent extension installation, Safari support from the Chromium ZIP, or interception of protected macOS shortcuts. Explain platform differences in the product and the release notes.

Build a testable `.app` on a real Mac before claiming the port works. Validate permissions, Retina/mixed-display coordinates, smooth selection, clipboard behavior, background lifecycle, and browser-to-native transfer. Document the supported macOS versions and architectures based on actual builds. Signing/notarization and Mac App Store distribution are separate release tasks; this repo contains no Apple signing identity or Team ID.

The current Windows browser tests include a real Edge extension-load/menu-registration check, a page-rendering/stitching harness, and an actual native-host-to-app image transfer. They do **not** establish macOS support or complete interactive coverage of every browser. See the release notes for limitations.

## Suggested initial request for Claude

> Read AGENTS.md, CLAUDE.md, docs/ARCHITECTURE.md, docs/MACOS-PORT.md, DESIGN.md, and the referenced source. Implement Grabpic as a native macOS app under macos/, preserving the Windows app. Start with menu-bar lifecycle, permissions, full-screen/area capture, local saving/clipboard, settings, and latest-capture restoration; then add configurable shortcuts and the browser native host. Follow the existing dark design system with regular font weights. Build and visually QA on macOS, use isolated test data, and report any unavailable permissions, hardware, signing credentials, or browser tests accurately. Do not claim untested features or publish a signed release without the necessary account configuration.
