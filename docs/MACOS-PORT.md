# Grabpic macOS port: implementation handoff

Prepared 28 October 2026 from the Windows 0.6.0 source. This file is a proposed plan and acceptance contract. **No macOS implementation, build, signing identity, or verified Mac behavior is included yet.** Read [CLAUDE.md](../CLAUDE.md) and [ARCHITECTURE.md](ARCHITECTURE.md), then inspect the source.

## Intended outcome

A native, polished macOS screenshot utility with the same Grabpic identity and core behavior: quick capture, automatic local saving, clipboard copying, organized folders, configurable input, and quiet background operation. Start with a normal launchable `.app` for the owner to test. Mac App Store submission is a separate later decision; a Microsoft Store MSIX or Windows EXE cannot serve as the Mac build.

Preserve the working Windows app and shared browser source. Add the new implementation under `macos/` and new platform-specific build/test instructions. Do not rewrite the existing Windows app just to host a Mac port.

## Proposed technology direction

Use SwiftUI for the primary interface and AppKit where native window/menu/input control is needed. Evaluate ScreenCaptureKit for still capture and Core Graphics/ImageIO for image handling. A proposed initial deployment target is macOS 14 or later; **confirm actual API availability and required architectures against the Xcode SDK on the build Mac before committing to that target**. Do not silently require a newer OS by selecting a newer screenshot API overload.

This is a recommendation, not existing Swift code. Prefer a small set of focused native services over putting capture, permissions, persistence, input hooks, and all views in one file. The Windows app mixes those responsibilities for its current small scope; its behavior is the reference, not a required structural pattern.

Suggested layout (not created yet):

```text
macos/
  Grabpic.xcodeproj/                 # or a documented reproducible equivalent
  Grabpic/
    App/                            # app lifecycle, menu bar, commands
    Capture/                        # display enumeration, screenshot, area overlay
    Settings/                       # model, migrations, local persistence
    Storage/                        # filenames, dates, PNG/JPEG, latest capture
    Clipboard/                      # pasteboard writes and optional monitoring
    Shortcuts/                      # recorder, registration, conflicts, permissions
    BrowserBridge/                  # framing/IPC integration and manifest management
    UI/                             # Capture/Settings, reusable controls and tokens
    Resources/Assets.xcassets/
  NativeHost/                       # separate command-line native messaging executable
  Tests/
  scripts/
  README.md
```

## Platform replacement map

| Existing Windows implementation | Proposed macOS direction / constraint |
|---|---|
| WPF MainWindow/Theme.xaml | SwiftUI views and AppKit windows using the shared visual tokens |
| WinForms NotifyIcon | SwiftUI MenuBarExtra or AppKit NSStatusItem; evaluate activation policy/Dock behavior |
| Graphics.CopyFromScreen | ScreenCaptureKit still capture; explicitly handle permissions, filters, scale, and pixel output |
| WPF AreaOverlay/DrawingVisual | Borderless AppKit NSPanel/NSWindow overlays with layer-backed drawing; freeze capture once |
| Win32 physical coordinates / virtual screen | NSScreen/CGDisplay identity, coordinate conversion, negative origins, Retina backing scale |
| Clipboard notifications + sequence numbers | NSPasteboard and changeCount observation; suppress the app's own image writes |
| RegisterHotKey / low-level hooks | Evaluate supported macOS shortcut APIs and event taps; permissions depend on mechanism |
| Windows virtual-key/modifier codes | A separate macOS key-code/modifier model; explicit migration/mapping if needed |
| Windows Run / StartupTask | ServiceManagement login-item APIs such as SMAppService with user-visible status |
| Named pipe and Windows mutex | Native app activation plus authenticated same-user local IPC, chosen for distribution model |
| Registry NativeMessagingHosts | Browser-specific native-host JSON locations on macOS, absolute executable paths |
| Explorer menu / COM DLL | Menu-bar commands first; Finder integration requires a separate supported extension/Services investigation |
| GDI+ PNG/JPEG | ImageIO/Core Graphics with explicit format, color metadata, and quality conversion |
| Program Files / LocalAppData | App bundle + Application Support; user-chosen captures directory; sandbox-aware access |
| ICO/Windows tile assets | Asset catalog/macOS icon assets derived from existing SVG/PNG; appropriate menu-bar rendering |
| Inno/MSIX/SignTool | Mac build/archive, code signing, notarization or Mac App Store route, with account configuration |

Use only public supported platform APIs. Do not fabricate Windows-style hooks into Finder/browser menus, disable browser protections, or silently alter managed-browser policies to sideload an extension.

## Core feature parity

| Feature | Expected Mac behavior | Windows reference |
|---|---|---|
| Full screen | Capture display under pointer; optional all-visible-display output | `Native.Capture`, MainWindow.BeginCapture |
| Area | Crosshair, smooth drag, frozen background, Escape cancels, correct pixel crop | AreaOverlay.cs |
| Save + copy | Default PNG, default copy enabled, background save, no main-window activation | MainWindow.Finish |
| Date folders | Daily/ISO weekly/monthly, local time, correct ISO week-year | Preferences.Subfolder |
| Image settings | PNG/JPG, JPG quality default 100, user-selected folder | Preferences.SaveImage / SettingsPage |
| Latest capture | Restore image/path when explicitly opened, including after restart | RecentCapture / ShowApp |
| Shortcuts | Record full/area/open-folder bindings; conflicts and invalid combinations explained | Shortcuts.cs |
| Mouse bindings | Optional parity after keyboard path; respect other apps and primary mouse actions | ShortcutService / ShortcutRecorder |
| Background lifecycle | Menu-bar operation; close hides settings; explicit Quit exits | App.xaml / App.xaml.cs |
| Login launch | Configurable native login item; background start without opening settings | Integration.Startup |
| Clipboard monitor | Off by default; image-only; own-write suppression; no duplicate-save loops | MainWindow.ClipboardTick |
| Browser full page/view/area | Shared extension with new Mac host, same local save settings | browser-extension/shared + BrowserBridge |
| Dark design | Regular weights, consistent hierarchy, custom restrained scrolling | DESIGN.md / Theme.xaml |

No annotation editor, screen recording, OCR, cloud upload, or extension-free scrolling engine is implemented by the Windows 0.6.0 baseline. The extension-free scrolling idea was discussed with the owner but not built. Do not count those as existing parity requirements or claim them in a Mac release.

## Capture, coordinate, and performance requirements

1. Obtain the necessary screen-capture authorization and show a clear permission state. A denied/revoked permission must not produce a blank image reported as successful. Provide a path to the appropriate system settings when needed.
2. Exclude Grabpic's own settings/overlay windows from the captured result or capture before showing the overlay. Avoid introducing a visible main-window flash for each capture.
3. Keep points, display-local pixels, global display coordinates, and image row direction explicit. Do not apply one global scale to every monitor. Test displays above/left of the primary, different backing scales, display hot-plug, and non-main pointer display.
4. For all displays, define an output composition strategy for mixed-density monitors, gaps, and color spaces. Document it and verify saved pixel dimensions. A union measured in points is not automatically a full-resolution pixel bitmap.
5. Freeze the background once per area-selection session. Redraw only selection/dimming layers on pointer changes; coalesce at the display/update cadence. Avoid PNG encode/decode or full-desktop recapture for every mouse move.
6. Keep encoding, disk IO, browser transfers, and large-image decoding off the UI thread. Return status updates on the main actor. Make capture/save state and cancellation explicit.
7. Preserve pixel quality and color metadata where supported. Test SDR first; document HDR/wide-gamut limits based on evidence. Do not claim perfect HDR parity from a single screenshot.
8. Escape and tiny/invalid selections must not save an empty file or replace the clipboard/latest capture. Restore focus sensibly to the user's previous application.

Useful official references: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager), [Core Graphics](https://developer.apple.com/documentation/coregraphics), [AppKit NSScreen](https://developer.apple.com/documentation/appkit/nsscreen). Check availability of the exact methods you use in Xcode; newer overloads can have a later minimum OS.

## Permissions and sandbox decisions

Keep permission requests tied to the feature requiring them. Screen capture, global event observation/interception, chosen-folder access, clipboard monitoring, and login items are separate concerns. The API/distribution mechanism determines which Screen Recording, Accessibility, or Input Monitoring prompts/permissions apply; do not claim they are all always required, or bypass them.

If using an App Sandbox build, persist user-chosen output-folder access using a supported security-scoped bookmark flow. Handle stale bookmarks, moved/deleted folders, revoked access, read-only volumes, and disk-full errors. Decide how the app and separately browser-launched native host communicate under the chosen sandbox/signing model; do not assume shared access to an arbitrary Application Support directory.

A direct-distribution app and a Mac App Store sandboxed app may need different installation/host-registration arrangements. Document these as separate build/distribution choices. Validate browser-host installation feasibility under actual App Store rules before claiming that the sandboxed app can write every browser's manifest directory.

Use native login-item state and surface any user approval needed. Do not automatically re-enable login launch after the user disables it. See [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

## Background lifecycle and shortcuts

Use a menu-bar item for Full screen, Area, Open captures, Open Grabpic, and Quit. Closing settings does not quit. A capture from the menu bar/shortcut/browser must not activate/reopen settings. An explicit open action does activate settings and restore the latest saved capture.

Preserve the filled purple camera app/Dock identity. For the menu-bar status item, test macOS template rendering and contrast in light/dark menu bars; any deliberate monochrome status-item adaptation should be documented while keeping the camera shape consistent.

Do not blindly translate Win to Command. macOS owns common screenshot/system shortcuts, including Command+Shift+3/4/5. Start by evaluating Control+Shift+1/2/3 (matching the current logical defaults), check conflicts, and allow user configuration. The final defaults must be tested on the chosen OS version and layout.

Recorder acceptance: left/right modifiers, non-US layouts, Escape cancellation, duplicate combinations, modifier-only attempts, held-key repeats, external conflicts, permission denial/revocation, and persistence failure. Keep the old binding when changing to a new one fails. Do not suppress global primary mouse actions without an intentional supported binding. Avoid logging typed text. See [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) and [AppKit](https://developer.apple.com/documentation/appkit).

## Persistence and saving

Use a platform-appropriate settings store and Application Support directory; keep a versioned schema. Reuse logical values and defaults from ARCHITECTURE.md, not raw Windows key-code integers. An importer is optional; if provided, explicitly map compatible fields and ask the user to reselect Windows-only folder paths and unsupported shortcuts.

Keep latest-capture state separate from the clipboard: the clipboard is transient, the saved image/path survives restart. If a saved file was deleted or its volume is offline, show an empty/recoverable state rather than crash or leave a stale thumbnail. Avoid blocking startup on a deep recursive scan of a large folder.

Save captures with unique filenames and a reliable completion acknowledgment. Prefer writing an image to a temporary file and atomically moving it into place. Never overwrite an unrelated image. Clipboard failure should not erase a successfully saved file; distinguish "saved" from "saved and copied". Translate JPG quality 100 to the native encoder's maximum correctly; JPEG remains lossy.

For clipboard monitoring, use a change marker/token to distinguish external images from your own clipboard writes. Debounce multiple formats of one image into one save. Do not save text, poll at excessive frequency, or assume pasteboard privacy behavior is identical across macOS versions. Test normal operation and permission/privacy changes on the supported OS.

## Browser extension and native host

Reuse `browser-extension/shared/` after validating the APIs on macOS. Create a Mac-native command-line host instead of shipping GrabPic.BrowserHost.exe. Its executable path in the host manifest must be absolute and executable. It should live at a stable signed installed location; handle app moves, upgrades, and uninstallation without leaving a host that points to a deleted version.

Preserve `com.owl.grabpic` and the JSON message contract in ARCHITECTURE.md for compatibility unless deliberately versioning both sides. Host stdout must contain framed JSON only; write diagnostics to stderr. Read exactly the length prefix and payload, enforce bounds before allocation/decoding, accept partial reads, and reject malformed/unsupported input.

Initial protocol tests: ping, area-dispatch acknowledgment, PNG save with settings, invalid action, malformed base64/PNG, huge dimensions, oversized encoded payload, app cold start, app already running, busy capture, save failure, connection timeout, cancellation, host termination, and cleanup of successful/failed transfers. A 96 MiB application read ceiling is not Chrome's transfer allowance; current Chrome documentation specifies a 64 MiB extension-to-host message ceiling and base64 increases size.

Chrome's default per-user manifest directory is `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`. Chromium and Chrome for Testing use different documented locations. For Firefox and Edge, verify their current macOS locations and policies from the vendors rather than copying Windows registry code. Native manifests use Chromium `allowed_origins` or Firefox `allowed_extensions` as appropriate. Check the actual published extension ID against the development ID before release.

References: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Mozilla native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging), [Edge native messaging](https://learn.microsoft.com/en-us/microsoft-edge/extensions-chromium/developer-guide/native-messaging).

The owner prefers **Settings → Install browser extension → Grabpic website → browser approval**. Preserve that user journey where supported, but document reality: Chrome on ordinary Windows/macOS requires a Web Store-signed extension for direct user installation; self-hosting is not a consumer installation workaround. Development unpacked loading is a test path. Firefox has a separate signed self-distribution path. Public extension publication/signing is not complete just because the Windows app or the Mac app was published. See [Chrome distribution](https://developer.chrome.com/docs/extensions/how-to/distribute) and [Firefox self-distribution](https://extensionworkshop.com/documentation/publish/self-distribution/).

Safari is a separate integration project. Investigate Safari Web Extensions/native messaging and packaging independently; do not claim these Chromium/Firefox ZIPs install into Safari unchanged. Browser context-menu entries cannot be supplied by Finder or a generic desktop screenshot service.

## Visual system on macOS

Use [DESIGN.md](../DESIGN.md) as the shared reference. Use the system macOS font through native APIs rather than bundling Segoe UI or copying SF font binaries. Preserve regular weight and the hierarchy; Windows DIPs and macOS points are platform-specific units, so verify visual results instead of doing a blind numeric conversion.

| Element | Reference size / intent |
|---|---|
| Main title | 28; regular |
| Hero heading | 26; regular |
| Main capture action | 19; regular |
| Section labels/titles | 15–16, or 10 for quiet uppercase group labels |
| Body and controls | 13–14 |
| Supporting copy | 12 |
| Metadata | 10–11 |

Palette: canvas `#14151B`, sidebar `#191A22`, cards `#1D1E28`, hero `#272337`, accent `#A294FA`, text `#EEEFF5`, muted `#A3A4B5`, border `#30313E`. Spacing uses a 4-unit basis; typical gaps 8/12/16/20/24/28/36; card radius 12; control radius 7–8.

Default to dark even if the system is light. Keep controls, dropdowns, recorder sheets, scrollbars, empty states, disabled controls, and permission/error states consistent. Maintain keyboard focus indication, VoiceOver names, reduced-motion behavior, and contrast. Adapt titlebar/traffic-light placement and standard Mac keyboard navigation naturally. Do not add a Workspace heading below the brand.

Source artwork: `src/GrabPic/Assets/GrabPic.svg`, `GrabPic-128.png`, `GrabPic-256.png`, and `docs/images/icon.png`. `tools/Build-Icons.ps1` contains the code-native drawing geometry. Create proper Mac assets; don't rename an ICO to ICNS. Review [Apple typography](https://developer.apple.com/design/human-interface-guidelines/typography) and [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).

## Acceptance checklist

Record actual macOS version, Xcode version, architecture, display arrangement/scales, browser versions, and signing/sandbox configuration with the QA report. Generated test patterns and isolated settings must be used for shareable screenshots.

- [ ] Build a launchable app on macOS; document reproducible commands and dependencies.
- [ ] Launch normally, hide/close settings, capture repeatedly, reopen, quit, and relaunch without duplicate status items/processes.
- [ ] Deny, grant, and revoke capture permission; show useful states without blank-success captures.
- [ ] Capture pointer display and all displays; test Retina, non-Retina/mixed scales, negative origins, Spaces, and display disconnect.
- [ ] Drag in each direction, cross displays where supported, cancel, attempt tiny selection, and verify exact saved pixel dimensions.
- [ ] Inspect selection responsiveness; keep encoding and disk IO off the drawing path.
- [ ] Verify PNG pixels, JPG quality control, default quality 100, local dates, New Year ISO-week boundaries, unique filenames, and folder changes.
- [ ] Verify slow/read-only/offline folders, stale access bookmarks, disk-full errors, and no accidental overwrite.
- [ ] Paste a capture into another app; verify clipboard-busy failure leaves the saved file intact.
- [ ] Enable optional clipboard saving, copy external image/text, check no duplicate/self-save loops, then disable it.
- [ ] Reopen after restart and recover the latest image; handle deleted images and stale async navigation.
- [ ] Record valid/conflicting/modifier-only/reserved bindings; test repeat suppression, keyboard layout, mouse behavior, failed persistence, and permission changes.
- [ ] Enable/disable login launch and verify no main-window flash; respect a system-disabled login item.
- [ ] Load companion extension in each claimed browser; test actual right-click → capture → Mac host → app → folder/clipboard, not only mocked APIs.
- [ ] Test full-page standards/quirks modes, long/wide pages, zoom/Retina, fixed headers, last-tile overlap, lazy-load change rejection, cancellation, tab switch, size limit, and bottom-right image pixels.
- [ ] Test encoded native-message byte limits, malformed input, cold-start timeout, concurrent actions, save acknowledgment, and transfer cleanup.
- [ ] Visually inspect app, overlay, progress popup, menus, scrollbars, icons, empty/error/permission states, keyboard focus, and accessibility.
- [ ] Validate supported architectures and minimum macOS version on actual hardware/runners before advertising them.
- [ ] For distribution, separately validate signing, nested host signing, notarization/Gatekeeper or App Store sandbox rules, upgrades, host path stability, and uninstall cleanup.

The Windows `--verify` suite and `tools/Test-Browser.cjs` are reference test cases, not proof of a Mac build. Current Playwright helpers contain Windows executable and user-runtime paths; adapt them and test a real signed/native host on Mac.

## Build sequence and delivery

1. Capture the feature baseline; create the native project and shared design tokens under `macos/`.
2. Implement lifecycle, permissions, display capture, area overlay, saving/clipboard, latest image, and settings. Build and run the first normal `.app`.
3. Add validated shortcuts, optional clipboard monitoring, and login items with the appropriate platform permission handling.
4. Implement the native browser host/manifest setup, reuse extension assets, and verify actual browser workflows.
5. Complete visual and behavior QA, add Mac-specific build documentation and CI where available, and produce a testable `.app`/archive.
6. Choose direct distribution versus Mac App Store, configure the owner's real Apple identity, and validate the chosen signing/sandbox path. Do not invent a Team ID, bundle ID reservation, publisher account, or certificate.

Deliver source, an opening/build entry point, test instructions, screenshots from generated content, a parity/status checklist, and known limitations. Preserve GPL-3.0 and applicable notices. There are no Apple credentials in this repository, and this Windows workspace cannot verify a native Mac app.
