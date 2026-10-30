import AppKit
import SwiftUI

// QA-only renderer: produces deterministic preview images from generated content so design
// reviews do not require screen-recording permission or the owner's desktop.
@main
enum PreviewRenderer {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write("usage: PreviewRenderer <output-directory>\n".data(using: .utf8)!)
            exit(1)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let profile = output.appendingPathComponent(".profile", isDirectory: true)
        setenv("GRABPIC_PROFILE_DIRECTORY", profile.path, 1)

        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: .darkAqua)

        let state = AppState(enableServices: false)
        state.status = "Ready when you are."

        let sample = makeSampleImage()
        let sampleURL = output.appendingPathComponent("Grab_2026-10-28_14-32-08-123_ab12.png")
        if let data = CaptureStore.data(for: sample, format: 0, quality: 100) {
            try? data.write(to: sampleURL)
        }
        let bytes = (try? sampleURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        state.latest = LatestCapture(
            url: sampleURL,
            name: sampleURL.lastPathComponent,
            detail: "\(sample.width) × \(sample.height) · \(bytes / 1024) KB · Just now",
            image: ImageLoader.thumbnail(from: sample),
            pixelWidth: sample.width,
            pixelHeight: sample.height
        )
        state.preferences.folder = output.appendingPathComponent("Captures").path

        let environment = RootView()
            .environmentObject(state)
            .environmentObject(state.preferences)

        render(environment, width: 1040, height: 760, to: output.appendingPathComponent("01-capture.png"))
        state.route = .settings
        render(environment, width: 1040, height: 760, to: output.appendingPathComponent("02-settings.png"))
        render(environment, width: 1040, height: 1840, to: output.appendingPathComponent("03-settings-full.png"))
        state.route = .capture
        render(environment, width: 900, height: 640, to: output.appendingPathComponent("06-capture-compact.png"))
        state.route = .settings
        render(environment, width: 900, height: 640, to: output.appendingPathComponent("07-settings-compact.png"))

        if let full = ImageLoader.cgImage(at: sampleURL) {
            let capture = LatestCapture(
                url: sampleURL,
                name: sampleURL.lastPathComponent,
                detail: state.latest?.detail ?? "",
                image: NSImage(cgImage: full, size: NSSize(width: full.width, height: full.height)),
                pixelWidth: full.width,
                pixelHeight: full.height
            )
            render(
                PreviewSheet(capture: capture)
                    .environmentObject(state)
                    .environmentObject(state.preferences),
                width: 860,
                height: 620,
                to: output.appendingPathComponent("04-preview.png")
            )
        }

        render(
            ShortcutRecorderView(
                action: .area,
                current: .ctrlShift(19),
                onCancel: {},
                onSave: { _ in nil }
            ),
            width: 460,
            height: 340,
            to: output.appendingPathComponent("05-shortcut-recorder.png")
        )

        print("Previews written to \(output.path)")
    }

    @MainActor
    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isOpaque = true
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -12000, y: -12000))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            FileHandle.standardError.write("Could not allocate render buffer\n".data(using: .utf8)!)
            return
        }
        representation.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        window.orderOut(nil)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("Could not encode \(url.lastPathComponent)\n".data(using: .utf8)!)
            return
        }
        do {
            try data.write(to: url)
            print("Rendered \(url.lastPathComponent)")
        } catch {
            FileHandle.standardError.write("Could not write \(url.path): \(error)\n".data(using: .utf8)!)
        }
    }

    static func makeSampleImage() -> CGImage {
        let width = 1600
        let height = 1000
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        let background = CGGradient(
            colorsSpace: space,
            colors: [
                NSColor(srgbRed: 0.09, green: 0.10, blue: 0.16, alpha: 1).cgColor,
                NSColor(srgbRed: 0.16, green: 0.14, blue: 0.25, alpha: 1).cgColor
            ] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(
            background,
            start: CGPoint(x: 0, y: height),
            end: CGPoint(x: width, y: 0),
            options: []
        )

        context.setFillColor(NSColor(srgbRed: 0.64, green: 0.58, blue: 0.98, alpha: 0.32).cgColor)
        context.fillEllipse(in: CGRect(x: 980, y: 480, width: 560, height: 560))
        context.setFillColor(NSColor(srgbRed: 0.36, green: 0.30, blue: 0.66, alpha: 0.28).cgColor)
        context.fillEllipse(in: CGRect(x: 1160, y: 620, width: 320, height: 320))

        func card(_ rect: CGRect, alpha: CGFloat) {
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: 26,
                cornerHeight: 26,
                transform: nil
            )
            context.addPath(path)
            context.setFillColor(NSColor(srgbRed: 0.13, green: 0.13, blue: 0.19, alpha: alpha).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
            context.setLineWidth(2)
            context.strokePath()
        }

        card(CGRect(x: 120, y: 520, width: 560, height: 320), alpha: 0.72)
        card(CGRect(x: 720, y: 520, width: 300, height: 320), alpha: 0.5)
        card(CGRect(x: 120, y: 300, width: 900, height: 170), alpha: 0.45)

        context.setFillColor(NSColor(srgbRed: 0.86, green: 0.85, blue: 0.96, alpha: 0.92).cgColor)
        context.fill(CGRect(x: 168, y: 736, width: 280, height: 22))
        context.setFillColor(NSColor(srgbRed: 0.86, green: 0.85, blue: 0.96, alpha: 0.4).cgColor)
        context.fill(CGRect(x: 168, y: 692, width: 410, height: 12))
        context.fill(CGRect(x: 168, y: 664, width: 350, height: 12))
        context.setFillColor(NSColor(srgbRed: 0.64, green: 0.58, blue: 0.98, alpha: 0.9).cgColor)
        context.fill(CGRect(x: 168, y: 572, width: 168, height: 44))

        return context.makeImage()!
    }
}
