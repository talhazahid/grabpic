# Grabpic 0.6.0

Adds the optional browser companion for Edge, Chrome, and Firefox, with a Grabpic right-click submenu:

- Full page: scroll and stitch one screenshot of an ordinary webpage.
- Visible view: capture the current webpage viewport.
- Area: use the existing native screen-area selector.

Browser captures use the Windows app's output folder, date grouping, PNG/JPG settings, and clipboard preference. Browser extensions must be enabled separately; the Windows installer/MSIX cannot silently enable them. Test extension ZIPs and a setup guide are included. Public distribution through browser stores requires separate publication/signing.

QA: 18 existing application checks passed. Edge-based automated browser tests passed for page stitching in standards and quirks mode (including partial final tiles and horizontal scrolling), fixed-header deduplication, original scroll and style restoration, bottom-right pixel integrity, oversized-page rejection, visible view, cancellation, and tab-switch rejection. The actual Chromium extension loaded successfully in Edge: its stable identity, Manifest V3 service worker, and installed scrolling-page context-menu entry were verified. Native framing and invalid-message checks passed. An actual PNG transfer through the native host to an isolated running app passed, including date-folder saving, latest-capture persistence, save acknowledgment, and temporary-file cleanup. Browser API calls in the stitching test use a harness backed by real Edge page rendering; this is not a claim of a complete interactive right-click capture test in every browser.

Firefox is not installed on the development PC and has not been run interactively. Chrome uses the Chromium extension bundle but was not independently tested. Browser-internal pages, PDFs, protected content, nested scrollers, virtualized lists, and changing/infinite feeds are not supported for full-page capture. Images are bounded to 60 megapixels and 32,700 pixels per dimension; document-size changes stop the capture rather than silently truncate it.

The Store package adds narrowly scoped flexible-virtualization exclusions and the restricted unvirtualizedResources capability for native-host discovery and local transfer folders. Partner Center review/approval is required. Local Store installation and packaged browser discovery remain unverified because this PC's existing certificate/sideload policy prevents MSIX installation. See [Store instructions](STORE.md) and [browser setup](BROWSERS.md).
