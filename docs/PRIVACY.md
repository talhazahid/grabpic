# Grabpic privacy policy

Effective date: 27 October 2026

Grabpic is an open-source Windows screenshot application published by Owl Dev.

## Your images stay local

Grabpic captures visible screen content when you request a screenshot. It saves images to a folder you choose and, by default, copies them to the Windows clipboard. The app does not upload screenshots, create an account, send analytics, or include advertising.

## Optional browser companion

The companion extension adds browser right-click capture actions. After you invoke an action, it reads the active page's dimensions and scroll position and captures webpage pixels. Full-page capture temporarily scrolls the page and hides repeated fixed elements, then restores the page. It communicates only with the local Grabpic native-messaging companion; it does not upload page content, collect browsing history, or send analytics. A temporary local PNG is removed after successful saving; unsuccessful transfers may leave an image in the app's local BrowserInbox folder, which you can delete. The extension must be enabled separately in each supported browser.

## Clipboard monitoring is optional

The option to save images copied from other apps is disabled by default. If you enable it, Grabpic reads image content from the clipboard and saves it locally while the app is running. Text clipboard contents are not saved by this feature. Turn the option off in Settings or quit Grabpic to stop monitoring.

## Shortcuts and preferences

Grabpic listens for shortcuts you assign so capture actions work in the background. It does not maintain a typing history or send keystrokes elsewhere. Local preferences store your capture folder, image format, quality, and shortcut assignments. A separate local file remembers the path to your latest saved capture.

## Windows and other software

Windows manages clipboard behavior, the system tray, Store installation, and startup permissions. If you choose a folder synchronized by OneDrive or another provider, that provider may synchronize your files under its own policy. Grabpic does not control third-party clipboard managers or cloud synchronization.

## Your control

Change these preferences in Settings, disable Windows startup, or quit the app from its tray menu. You can delete your images directly from your capture folder. For the standalone app, settings are stored under `%LOCALAPPDATA%\GrabPic`; Windows may redirect local state for a Store-installed package. Uninstalling does not intentionally remove your saved screenshots.

## Contact

For privacy questions, [open an issue in the Grabpic repository](https://github.com/talhazahid/grabpic/issues). Please do not attach sensitive screenshots, private clipboard content, or credentials to a public issue.
