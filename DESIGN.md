# Grab Pic visual system

The direction combines the orderly sidebar, compact controls, and restrained surfaces of macOS utility apps with Windows-native text and input behavior.

References reviewed:
- https://developer.apple.com/design/human-interface-guidelines/typography
- https://developer.apple.com/design/human-interface-guidelines/designing-for-macos
- https://developer.apple.com/design/human-interface-guidelines/color
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography

## Tokens

| Token | Value |
|---|---|
| Typeface | Segoe UI Variable; Segoe UI fallback |
| Weight | Regular 400; no 600 or 700 |
| Page title | 28 DIP |
| Hero title | 26 DIP |
| Action title | 19 DIP |
| Section title | 15–16 DIP |
| Body / controls | 13–14 DIP |
| Supporting text | 12 DIP |
| Shortcut / metadata | 10–11 DIP |
| Text | #EEEFF5 |
| Secondary text | #A3A4B5 |
| Accent | #A294FA |
| Canvas | #14151B |
| Sidebar | #191A22 |
| Hero | #272337 |
| Card | #1D1E28 |
| Border | #30313E |
| Spacing unit | 4 DIP; most gaps 8, 12, 16, 20, 24, 28, 36 |
| Card radius | 12 DIP |
| Control radius | 7–8 DIP |

Hierarchy uses size, spacing, grouping, and contrast. No bold typography. Controls share border and corner treatments, labels use sentence case, and the accent marks selection and capture actions. Custom buttons and checks expose keyboard focus. Settings save immediately with status feedback.

Segoe UI Variable follows Microsoft's Windows recommendation. Apple’s typography guidance informs hierarchy and restraint; its point sizes are not treated as interchangeable with Windows DIPs.

Dark mode is the default. Scrollbars use a quiet rounded thumb, no arrow buttons, and a transparent track. The sidebar contains Capture and Settings directly below the logo, without a Workspace label. Input recording dialogs, combo popups, sliders, checks, and the tray menu share the dark palette.
