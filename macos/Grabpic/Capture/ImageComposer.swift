import CoreGraphics
import Foundation

enum ImageComposer {
    /// Union of every visible display in AppKit global points.
    static func union(of shots: [DisplayShot]) -> CGRect {
        shots.reduce(CGRect.null) { $0.union($1.frame) }
    }

    static func fullImage(from shots: [DisplayShot]) -> CGImage? {
        guard !shots.isEmpty else { return nil }
        if shots.count == 1 { return shots[0].image }
        return compose(shots: shots, rect: union(of: shots))
    }

    /// Crops or composes the requested global-point rectangle. A selection inside one display
    /// is cropped at native pixel resolution; cross-display selections are composed at the
    /// highest density involved, with unused gaps filled quietly.
    static func compose(shots: [DisplayShot], rect: CGRect) -> CGImage? {
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let involved = shots.filter { $0.frame.intersects(rect) }
        guard !involved.isEmpty else { return nil }
        if involved.count == 1, let shot = involved.first {
            return crop(shot, to: rect)
        }

        let scale = involved.map(\.scale).max() ?? 1
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))
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

        context.setFillColor(CGColor(srgbRed: 0x10 / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        for shot in involved {
            let local = shot.frame.intersection(rect)
            guard local.width >= 1, local.height >= 1 else { continue }

            let sourceX = Int(round((local.minX - shot.frame.minX) * shot.scale))
            let sourceY = Int(round((shot.frame.maxY - local.maxY) * shot.scale))
            let sourceWidth = max(1, Int(round(local.width * shot.scale)))
            let sourceHeight = max(1, Int(round(local.height * shot.scale)))
            let source = CGRect(x: sourceX, y: sourceY, width: sourceWidth, height: sourceHeight)
                .intersection(CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height))
            guard !source.isNull, source.width >= 1, source.height >= 1,
                  let cropped = shot.image.cropping(to: source.integral) else { continue }

            let destination = CGRect(
                x: (local.minX - rect.minX) * scale,
                y: (rect.maxY - local.maxY) * scale,
                width: local.width * scale,
                height: local.height * scale
            )
            context.draw(cropped, in: destination)
        }

        return context.makeImage()
    }

    static func crop(_ shot: DisplayShot, to rect: CGRect) -> CGImage? {
        let local = shot.frame.intersection(rect)
        guard local.width >= 1, local.height >= 1 else { return nil }
        var pixelRect = CGRect(
            x: (local.minX - shot.frame.minX) * shot.scale,
            y: (shot.frame.maxY - local.maxY) * shot.scale,
            width: local.width * shot.scale,
            height: local.height * shot.scale
        ).integral
        pixelRect = pixelRect.intersection(
            CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        )
        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return shot.image.cropping(to: pixelRect)
    }
}
