<p align="center"><img src="docs/images/icon.png" width="88" alt="Grabpic purple camera icon"></p>
<h1 align="center">Grabpic</h1>
<p align="center">Capture. Copy. Carry on.</p>
<p align="center">A quiet, local screenshot utility for Windows and macOS.<br>Full screen, a selected area, and an organized folder. Ready to paste.</p>
<p align="center"><a href="https://github.com/talhazahid/grabpic/releases/tag/macos-v0.7.0">Download for macOS</a> · <a href="https://github.com/talhazahid/grabpic/releases/tag/v0.6.0">Download for Windows</a> · <a href="https://talhazahid.github.io/grabpic/">Website</a> · <a href="https://github.com/talhazahid/grabpic/issues">Report an issue</a></p>

## Choose your platform

| | macOS 0.7.0 | Windows 0.6.0 |
|---|---|---|
| Download | [Apple silicon ZIP](https://github.com/talhazahid/grabpic/releases/download/macos-v0.7.0/Grabpic-0.7.0-macOS-arm64.zip) | [x64 installer](https://github.com/talhazahid/grabpic/releases/download/v0.6.0/GrabPic-Setup-0.6.0-x64.exe) |
| Requires | macOS 14+ · Apple silicon | Windows 11 · Intel/AMD x64 |
| Full screen and area screenshots | Yes | Yes |
| PNG / JPG, clipboard copy, date folders | Yes | Yes |
| Full screen and area recording | MP4 · system audio · optional microphone | — |
| Background access | Menu bar and keyboard shortcuts | Tray, desktop menu, keyboard and mouse shortcuts |
| Browser scrolling capture | — | [Optional companion](docs/BROWSERS.md) |

The Mac download is ad-hoc signed and not notarized. Gatekeeper may block it; see [installation and limitations](macos/README.md). Intel Mac builds are not provided. Windows downloads and its release workflow remain available independently.

## Meet Grabpic for Mac

Native SwiftUI and AppKit, with the same purple camera and calm dark interface.

![Grabpic for macOS — capture and recording controls with a generated sample image](macos/docs/screenshots/capture.png)

- Full screen or a selected area. Capture the display under the pointer, all displays, or drag a rectangle.
- Ready to paste. Screenshots save locally and copy to the clipboard by default.
- Keep things tidy. Choose your folder and group captures by day, ISO week, or month.
- Record a moment. Record a screen or area to MP4, with system audio and optional microphone audio. Choose 30 or 60 fps, full resolution or 1080p, and pointer visibility.
- Stay in your flow. Capture from the menu bar or a shortcut without opening the main window. Open the app explicitly to restore the latest capture.
- Make it yours. Record keyboard shortcuts, enable start at login, and switch capture flash, shutter sound, or the menu bar icon on or off.

<details>
<summary>macOS settings and shortcut recorder</summary>

![Grabpic macOS settings](macos/docs/screenshots/settings.png)

![Grabpic macOS shortcut recorder](macos/docs/screenshots/recorder.png)

</details>

### Install on macOS

1. Download and unzip `Grabpic-0.7.0-macOS-arm64.zip` from the [macOS release](https://github.com/talhazahid/grabpic/releases/tag/macos-v0.7.0).
2. Move `Grabpic.app` to Applications before enabling start at login.
3. Open the app. This build has no Developer ID or notarization; macOS may require an explicit approval in System Settings → Privacy & Security. Only approve a download whose source you trust.
4. Grant Screen Recording permission when prompted, then relaunch. Microphone permission is needed only when microphone recording is enabled.

The deployment target is macOS 14; this build was verified on an Apple silicon Mac running macOS 26.6.2. Other OS versions and physical multi-display configurations have not been verified in this release. Browser capture, mouse shortcuts, and Finder integration are not included on Mac. See [Mac documentation](macos/README.md) for the full test record and known limits.

## Grabpic for Windows

The Windows app runs quietly in the tray, with native desktop-menu capture and optional browser capture.

![Grabpic for Windows capture window](docs/images/01-capture.png)

1. Download the [Windows x64 installer](https://github.com/talhazahid/grabpic/releases/tag/v0.6.0) and run setup. The standard installer requests administrator access for its system-wide desktop menu; the .NET runtime is included.
2. Use a shortcut, the tray menu, or right-click empty desktop space → Grab Pic. On Windows 11, the standard installer's menu is under Show more options.
3. Paste your screenshot. A saved copy is already in your capture folder.

Windows supports configurable keyboard and mouse bindings, including Windows-key combinations such as Win + Shift + S. Protected security shortcuts cannot be reassigned. Mouse bindings pause while the app is focused. Optional full scrolling-page and visible-webpage capture require the separately enabled [browser companion](docs/BROWSERS.md); browser-store publication is separate.

<details>
<summary>Windows shortcuts and saving settings</summary>

![Windows shortcut settings](docs/images/02-shortcuts.png)

![Windows saving settings](docs/images/03-saving.png)

</details>

[Microsoft Store listing](https://apps.microsoft.com/detail/9PJ3HBXBCTX1) — availability depends on Microsoft's approval and publication.

## Default shortcuts

| Action | Windows | macOS |
|---|---|---|
| Grab full screen | Ctrl + Shift + 1 | Control + Shift + 1 |
| Grab area | Ctrl + Shift + 2 | Control + Shift + 2 |
| Open captures | Ctrl + Shift + 3 | Control + Shift + 3 |
| Start / stop screen recording | — | Control + Shift + 5 |

Change bindings in Settings → Shortcuts. Mac shortcuts use keyboard combinations; combinations reserved by macOS or already assigned in Grabpic are declined.

## Local by design

No account, uploads, advertising, or analytics. Captures and preferences stay on your computer. Optional clipboard-image saving is off by default. A cloud-synced capture folder can still be synchronized by its provider. See the [privacy policy](docs/PRIVACY.md).

Closing the window keeps Grabpic running in the tray or menu bar; use Quit Grab Pic to exit. Captures use the visible desktop, not hidden virtual desktops or Spaces. Neither platform includes annotation, OCR, or cloud sharing. Protected content may be unavailable; HDR accuracy needs wider validation.

All product screenshots above use generated sample content, not personal captures.

## Build from source

### macOS

Xcode 15+ or a compatible Swift toolchain and macOS SDK; no third-party dependencies.

```bash
cd macos
./scripts/build.sh
./scripts/run-logic-tests.sh
./scripts/render-previews.sh
open build/Grabpic.app
```

See [macOS source, QA, and limitations](macos/README.md).

### Windows

Install the .NET 8 SDK, then use PowerShell on Windows:

```powershell
dotnet build src/GrabPic -c Release
dotnet run --project src/GrabPic
powershell -ExecutionPolicy Bypass -File tools/Build-Setup.ps1
```

Installer builds require Inno Setup 6.6+. For Store packaging, run `tools/Build-Store.ps1`; see [Store packaging](docs/STORE.md). Verify the published app with `dist/GrabPic/GrabPic.exe --verify verification.txt`.

### Project reference

[Architecture](docs/ARCHITECTURE.md) · [Design system](DESIGN.md) · [Contributor guide](CONTRIBUTING.md) · [Repository instructions](AGENTS.md) · [macOS parity plan](docs/MACOS-PORT.md)

## Open source

Grabpic is free software under the [GNU General Public License v3.0](LICENSE). Contributions and bug reports are welcome. Third-party notices remain in [packaging/Licenses](packaging/Licenses). ShareX was reviewed as research material; its source is not bundled or linked into the app.
