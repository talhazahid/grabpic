import Foundation
import ImageIO
import AppKit
import UniformTypeIdentifiers

enum ImageLoader {
    static func thumbnail(from image: CGImage, maxPixel: Int = 360) -> NSImage? {
        let scale = min(1, CGFloat(maxPixel) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: width, height: height))
    }

    static func cgImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func thumbnail(at url: URL, maxPixel: Int = 320) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    struct Metadata {
        let pixelWidth: Int
        let pixelHeight: Int
        let bytes: Int
    }

    static func metadata(at url: URL) -> Metadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Metadata(pixelWidth: width, pixelHeight: height, bytes: bytes)
    }
}

enum CaptureStore {
    static func data(for image: CGImage, format: Int, quality: Int) -> Data? {
        let uti = format == 0 ? UTType.png.identifier : UTType.jpeg.identifier
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti as CFString, 1, nil) else {
            return nil
        }
        var options: [CFString: Any] = [:]
        if format == 1 {
            // Map the 40...100 control directly to the native encoder's quality range.
            options[kCGImageDestinationLossyCompressionQuality] = CGFloat(min(max(quality, 0), 100)) / 100
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func pngData(for image: CGImage) -> Data? {
        data(for: image, format: 0, quality: 100)
    }

    /// Encodes to a temporary file in the destination folder and moves it into place under a
    /// collision-resistant name. An existing capture is never overwritten.
    static func save(_ image: CGImage, settings: CaptureSettings, date: Date = Date()) throws -> URL {
        try saveReturningData(image, settings: settings, date: date).url
    }

    /// Same as `save`, but also hands back the encoded bytes so callers can reuse them.
    static func saveReturningData(
        _ image: CGImage,
        settings: CaptureSettings,
        date: Date = Date()
    ) throws -> (url: URL, data: Data) {
        let manager = FileManager.default
        let folder = settings.folder.appendingPathComponent(
            DateFolder.name(for: date, organization: settings.organization),
            isDirectory: true
        )
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = uniqueURL(in: folder, date: date, format: settings.format)
        guard let encoded = data(for: image, format: settings.format, quality: settings.quality) else {
            throw CaptureError.encodingFailed
        }
        try encoded.write(to: url, options: .atomic)
        return (url, encoded)
    }

    /// The final name for a new screen recording, in the same dated folder as screenshots.
    static func recordingURL(settings: CaptureSettings, date: Date = Date()) throws -> URL {
        let folder = settings.folder.appendingPathComponent(
            DateFolder.name(for: date, organization: settings.organization),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for _ in 0..<12 {
            let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
            let url = folder.appendingPathComponent("Rec_\(timestamp(for: date))_\(suffix).mp4")
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return folder.appendingPathComponent("Rec_\(timestamp(for: date))_\(UUID().uuidString.prefix(8)).mp4")
    }

    private static func uniqueURL(in folder: URL, date: Date, format: Int) -> URL {
        let manager = FileManager.default
        for _ in 0..<12 {
            let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
            let url = folder.appendingPathComponent(fileName(date: date, format: format, suffix: suffix))
            if !manager.fileExists(atPath: url.path) { return url }
            usleep(1200)
        }
        return folder.appendingPathComponent(
            fileName(date: date, format: format, suffix: String(UUID().uuidString.prefix(8)))
        )
    }

    /// The single source of truth for capture names, shared with settings previews.
    static func fileName(date: Date, format: Int, suffix: String = "ab12") -> String {
        let extensionName = format == 0 ? "png" : "jpg"
        return "Grab_\(timestamp(for: date))_\(suffix).\(extensionName)"
    }

    static func timestamp(for date: Date) -> String {
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let milliseconds = (parts.nanosecond ?? 0) / 1_000_000
        return String(
            format: "%04d-%02d-%02d_%02d-%02d-%02d-%03d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, milliseconds
        )
    }

    enum CaptureError: LocalizedError {
        case encodingFailed
        var errorDescription: String? { "The image could not be encoded." }
    }
}

enum DateFolder {
    static func name(for date: Date, organization: Int) -> String {
        let calendar = Calendar.current
        switch organization {
        case 1:
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
        case 2:
            let parts = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        default:
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
    }
}
