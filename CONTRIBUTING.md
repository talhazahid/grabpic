# Contributing to Grabpic

Please open an issue describing the problem or proposed change before starting substantial work. Include your Windows version, display arrangement, and reproduction steps for capture issues; avoid private screenshots.

Build with the .NET 8 SDK on Windows. Keep the design consistent with DESIGN.md: regular text weights, a clear type hierarchy, dark surfaces, and the existing spacing and controls. Do not introduce 600 or 700 font weights.

Verify the behavior you changed and review the actual UI before submitting a pull request. `GrabPic.exe --verify <report-path>` checks capture encoding, folder rules, and shortcut validation. Interactive QA scripts use the running app and may change bindings, so run them against a disposable profile. `GRABPIC_PROFILE_DIRECTORY` selects an isolated local profile. Public screenshots must use the isolated screenshot script rather than real private desktop content.

Contributions are distributed under the repository's GPL-3.0 license.
