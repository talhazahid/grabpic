import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardService {
    /// Writes PNG immediately and promises TIFF lazily. Building an uncompressed TIFF of a Retina
    /// capture costs tens of megabytes and a noticeable pause, so it is only produced if an app
    /// actually asks for it.
    @discardableResult
    static func copy(_ image: CGImage) -> Bool {
        guard let png = CaptureStore.pngData(for: image) else { return false }
        return copy(png: png, image: image)
    }

    @discardableResult
    static func copy(png: Data, image: CGImage) -> Bool {
        let pasteboard = NSPasteboard.general
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        let provider = TIFFProvider(image: image)
        item.setDataProvider(provider, forTypes: [.tiff])
        TIFFProvider.current = provider
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
        /// The pasteboard holds providers weakly; keep the latest one alive until replaced.
        nonisolated(unsafe) static var current: TIFFProvider?
        private let image: CGImage

        init(image: CGImage) {
            self.image = image
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            guard type == .tiff else { return }
            if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
        }

        func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
            if TIFFProvider.current === self { TIFFProvider.current = nil }
        }
    }

    /// Copies a file the way Finder does: a file URL, the legacy filename list that older and
    /// Electron apps read, and (lazily, only if a receiving app asks) the movie's own data.
    @discardableResult
    static func copyFile(_ url: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL) else { return false }
        item.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        if url.pathExtension.lowercased() == "mp4" {
            let provider = FileDataProvider(url: url)
            item.setDataProvider(provider, forTypes: [NSPasteboard.PasteboardType("public.mpeg-4")])
            FileDataProvider.current = provider
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private final class FileDataProvider: NSObject, NSPasteboardItemDataProvider {
        nonisolated(unsafe) static var current: FileDataProvider?
        private let url: URL

        init(url: URL) {
            self.url = url
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                item.setData(data, forType: type)
            }
        }

        func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
            if FileDataProvider.current === self { FileDataProvider.current = nil }
        }
    }

    static func readImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        if let data = pasteboard.data(forType: .tiff),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        ) as? [URL],
           let url = urls.first,
           let image = ImageLoader.cgImage(at: url) {
            return image
        }
        if let image = NSImage(pasteboard: pasteboard),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        return nil
    }
}

/// Polls the pasteboard because macOS has no clipboard notification API. Own writes are
/// admitted by change count so Grab Pic never loops on its own captures.
@MainActor
final class ClipboardWatcher {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let interval: TimeInterval = 0.35
    var isEnabled = false {
        didSet {
            if isEnabled {
                lastChangeCount = NSPasteboard.general.changeCount
                start()
            } else {
                stop()
            }
        }
    }
    var shouldPause: (() -> Bool)?
    var onImage: ((CGImage) -> Void)?

    func markOwnWrite() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isEnabled else { return }
        if shouldPause?() == true { return }
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard let image = ClipboardService.readImage() else { return }
        onImage?(image)
    }
}
