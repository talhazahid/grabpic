# Repository instructions

- The owner speaks Urdu. Reply in English when the owner speaks Urdu.
- Follow the design system in [DESIGN.md](DESIGN.md). Use regular font weight; do not introduce 600/700 weights or semibold/bold styling. Create hierarchy with size, spacing, grouping, and contrast.
- Dark mode is the default. Keep the purple filled camera identity consistent across app, tray/menu bar, taskbar/Dock, installer, and browser assets. Do not add a Workspace label below the logo.
- Preserve background capture behavior: capturing must not open the main app window. Explicitly opening the app should restore the latest saved capture.
- Keep screenshots, clipboard images, preferences, and browser transfers local. No account, ads, analytics, or upload service is part of the product.
- QA changed behavior and inspect affected UI before calling work complete. State platform/testing limits honestly. Use disposable profiles and generated content for screenshots and tests.
- Preserve the Windows application and its release workflow when adding another platform. Put a new macOS implementation in `macos/`; this is a proposed directory, not an existing app.
- Read [CLAUDE.md](CLAUDE.md), [the architecture](docs/ARCHITECTURE.md), and [the macOS port guide](docs/MACOS-PORT.md) before porting.
- Preserve the GPL-3.0 license and third-party notices. Do not commit signing keys, certificates, account tokens, personal captures, local settings, downloaded reference repositories, or generated build folders.

These instructions document the owner's existing preferences. The macOS guide describes proposed work; it does not mean a macOS implementation has already been built or tested.
