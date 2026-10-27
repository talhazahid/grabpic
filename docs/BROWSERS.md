# Browser capture in Grabpic 0.6.0

Browser right-click menus are controlled by browser extensions, independently of the Windows desktop menu. Install the Windows app **and enable its companion extension** in each browser you use.

## Test the companion extension

1. Install Grabpic 0.6.0 and open it once to register the local browser bridge. Leave it running in the tray.
2. Extract `Grabpic-Browser-chromium-0.6.0.zip` from the submission bundle, or use the installed app's `BrowserExtensions/chromium` folder. In Edge open `edge://extensions`, or in Chrome open `chrome://extensions`. Enable Developer mode, choose **Load unpacked**, and select the extension folder. Keep its manifest key unchanged. For the MSIX build, extract the ZIP to a stable folder you own so package updates do not move the loaded extension path.
3. For Firefox, extract `Grabpic-Browser-firefox-0.6.0.zip`. Open `about:debugging#/runtime/this-firefox`, choose **Load Temporary Add-on**, and select its manifest.json. This temporary test installation ends when Firefox restarts.
4. Open an ordinary HTTP/HTTPS page, right-click, and choose **Grabpic**:
   - **Grab full page (scrolling)** scrolls horizontally and vertically and stitches one image.
   - **Grab visible view** captures the webpage viewport, excluding browser toolbars.
   - **Grab area** opens the existing Windows area-selection overlay.
5. The resulting image uses Grabpic's folder, date grouping, PNG/JPG, quality, and clipboard preferences. The main app stays in the background.

## Distribution and limitations

The Windows MSIX does not silently install browser extensions. Public browser-store distribution requires separate Edge Add-ons / Chrome Web Store publication and Mozilla signing. These ZIPs are development/testing packages, not signed browser-store releases. Firefox temporary add-ons require reloading after restart. Chromium-based browsers other than Chrome and Edge need separate native-host registration; arbitrary browsers are not claimed as supported.

Browser-internal pages, extension stores, protected content, PDFs, nested independently scrolling frames, virtualized lists, and infinite feeds may not support full-page capture. Only ordinary top-level document scrolling is supported. Fixed/sticky elements appear in the first tile and are hidden in later tiles to reduce repetition; their original inline visibility and the original scroll position are restored on success, cancellation, or handled failure. Use Cancel before closing the progress window. A page-side watchdog also attempts restoration after 30 seconds without capture activity; browser background-tab throttling can delay this fallback.

Wait for lazy-loaded pages to settle before capturing. If document size changes during capture, Grabpic stops with an error rather than silently cropping. Keep the original tab active and do not resize/zoom/navigate while capturing. Captures are limited to 60 megapixels and 32,700 pixels per dimension. Restricted pages and unsupported scroll containers show an error. Videos and continuously changing content cannot be frozen reliably.

## Privacy

The extension requests active-tab access only after a capture action, context-menu access, script execution for scroll positioning, and native messaging to the local Grabpic companion. It has no always-on page content script, analytics, network upload, or remote capture service. Screenshot pixels pass through a local temporary PNG and are deleted after a successful save. Failed transfers may leave a PNG under Grabpic's local `BrowserInbox` folder, which you can delete. Browsing history is not collected. See the [privacy policy](https://talhazahid.github.io/grabpic/privacy/).
