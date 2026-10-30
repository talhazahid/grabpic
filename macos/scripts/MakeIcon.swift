import AppKit

// Draws the Grab Pic camera identity as a native macOS icon: a padded rounded square with a
// restrained vertical gradient and the shared white camera outline.
let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: MakeIcon <output-directory>\n".data(using: .utf8)!)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let iconset = outputDirectory.appendingPathComponent("Grabpic.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let scale = size / 1024
    let inset = 100 * scale
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.225
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let colors = [
        NSColor(srgbRed: 0xB6 / 255, green: 0xA9 / 255, blue: 1.0, alpha: 1).cgColor,
        NSColor(srgbRed: 0x92 / 255, green: 0x84 / 255, blue: 0xF0 / 255, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    context.restoreGState()

    // A whisper of light along the top edge.
    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    context.setLineWidth(1.4 * scale)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: inset, y: inset + body.height)
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
    context.setLineWidth(5.5)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.strokePath()

    context.addEllipse(in: CGRect(x: 37, y: 41, width: 26, height: 26))
    context.strokePath()
    context.restoreGState()

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GrabpicIcon", code: 1)
    }
    try data.write(to: url)
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
var rendered: [Int: URL] = [:]
for size in sizes {
    let url = iconset.appendingPathComponent("icon-\(size).png")
    try writePNG(drawIcon(size: CGFloat(size)), to: url)
    rendered[size] = url
}

let names: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]
for (size, name) in names {
    guard let source = rendered[size] else { continue }
    let destination = iconset.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: source, to: destination)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("Grabpic.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print("Icon written to \(outputDirectory.appendingPathComponent("Grabpic.icns").path)")
