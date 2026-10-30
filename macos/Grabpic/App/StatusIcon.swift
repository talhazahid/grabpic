import AppKit

/// Menu bar artwork that keeps the filled purple camera identity instead of a
/// monochrome template glyph. The tile is drawn at the menu bar's optical size
/// so it sits comfortably beside system extras.
enum StatusIcon {
    static func make(height: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: height, height: height), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setShouldAntialias(true)
            context.interpolationQuality = .high

            let inset = bounds.width * 0.055
            let body = bounds.insetBy(dx: inset, dy: inset)
            let radius = body.width * 0.27
            let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

            context.saveGState()
            context.addPath(shape)
            context.clip()
            let colors = [
                NSColor(srgbRed: 0xB6 / 255, green: 0xA9 / 255, blue: 1, alpha: 1).cgColor,
                NSColor(srgbRed: 0x92 / 255, green: 0x84 / 255, blue: 0xF0 / 255, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: colors,
                locations: [0, 1]
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: body.midX, y: body.maxY),
                    end: CGPoint(x: body.midX, y: body.minY),
                    options: []
                )
            }
            context.restoreGState()

            // The same camera outline used by the dock and app icon, thinned so the
            // small tile stays legible.
            context.saveGState()
            context.translateBy(x: body.minX, y: body.maxY)
            context.scaleBy(x: body.width / 100, y: -body.width / 100)

            let camera = CGMutablePath()
            camera.move(to: CGPoint(x: 34, y: 33))
            camera.addLine(to: CGPoint(x: 40, y: 24))
            camera.addLine(to: CGPoint(x: 60, y: 24))
            camera.addLine(to: CGPoint(x: 66, y: 33))
            camera.addLine(to: CGPoint(x: 74, y: 33))
            camera.addArc(tangent1End: CGPoint(x: 82, y: 33), tangent2End: CGPoint(x: 82, y: 41), radius: 7)
            camera.addLine(to: CGPoint(x: 82, y: 68))
            camera.addArc(tangent1End: CGPoint(x: 82, y: 75), tangent2End: CGPoint(x: 74, y: 75), radius: 7)
            camera.addLine(to: CGPoint(x: 25, y: 75))
            camera.addArc(tangent1End: CGPoint(x: 18, y: 75), tangent2End: CGPoint(x: 18, y: 68), radius: 7)
            camera.addLine(to: CGPoint(x: 18, y: 40))
            camera.addArc(tangent1End: CGPoint(x: 18, y: 33), tangent2End: CGPoint(x: 25, y: 33), radius: 7)
            camera.closeSubpath()

            context.addPath(camera)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(6.5)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.strokePath()

            context.addEllipse(in: CGRect(x: 37, y: 41, width: 26, height: 26))
            context.strokePath()
            context.restoreGState()

            return true
        }
        image.isTemplate = false
        return image
    }

    /// Shown while a recording runs: the camera tile turns red, with a white record dot. `level`
    /// (0...1) drives a gentle pulse so the menu bar reads "recording" at a glance.
    static func recording(height: CGFloat = 18, level: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: height, height: height), flipped: false) { bounds in
            let inset = bounds.width * 0.055
            let body = bounds.insetBy(dx: inset, dy: inset)
            let radius = body.width * 0.27
            let tile = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
            let alpha = 0.55 + 0.45 * max(0, min(1, level))
            NSColor(srgbRed: 0.94, green: 0.29, blue: 0.32, alpha: alpha).setFill()
            tile.fill()

            // Soft halo that grows and fades with the pulse.
            let haloSide = body.width * (0.46 + 0.16 * (1 - level))
            let halo = CGRect(x: body.midX - haloSide / 2, y: body.midY - haloSide / 2, width: haloSide, height: haloSide)
            NSColor.white.withAlphaComponent(0.28 * level).setFill()
            NSBezierPath(ovalIn: halo).fill()

            let dotSide = body.width * 0.38
            let dot = CGRect(x: body.midX - dotSide / 2, y: body.midY - dotSide / 2, width: dotSide, height: dotSide)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
