import AppKit
import CoreGraphics
import QuartzCore

/// Freezes every display, then presents one borderless overlay per screen. A drag may cross
/// displays; each overlay renders its intersection of the same global selection rectangle.
@MainActor
final class AreaSelector {
    static let shared = AreaSelector()

    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var selection: CGRect?
    private var startPoint: CGPoint?
    private var previousApp: NSRunningApplication?
    private var escapeMonitor: Any?
    private var isFinishing = false
    private var bounds: CGRect = .null
    private var screenObserver: NSObjectProtocol?

    func select(
        shots: [DisplayShot],
        hint: String = "Drag to grab an area   ·   Esc to cancel"
    ) async -> CGRect? {
        guard windows.isEmpty, continuation == nil, !shots.isEmpty else { return nil }
        bounds = ImageComposer.union(of: shots)
        previousApp = NSWorkspace.shared.frontmostApplication
        let pointerScreen = CaptureService.shared.screenUnderPointer()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            build(shots: shots, pointerScreen: pointerScreen, hint: hint)
        }
    }

    private func build(shots: [DisplayShot], pointerScreen: NSScreen?, hint: String) {
        NSCursor.crosshair.push()
        var keyWindow: NSWindow?

        for shot in shots {
            let screen = NSScreen.screens.first(where: {
                (CaptureService.shared.displayID(for: $0) ?? 0) == shot.screenID
            })
            let window = OverlayWindow(
                contentRect: shot.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(shot.frame, display: true)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = false

            let isPointerScreen = screen != nil && screen == pointerScreen
            let view = SelectionView(
                frame: CGRect(origin: .zero, size: shot.frame.size),
                image: shot.image,
                scale: shot.scale,
                controller: self,
                hint: isPointerScreen ? hint : nil
            )
            window.contentView = view
            views.append(view)
            windows.append(window)
            if isPointerScreen { keyWindow = window }
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            window.orderFrontRegardless()
        }
        (keyWindow ?? windows.first)?.makeKey()
        if let view = (keyWindow ?? windows.first)?.contentView {
            (keyWindow ?? windows.first)?.makeFirstResponder(view)
        }

        // A display added, removed, or rearranged mid-selection invalidates the frozen frames.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
    }

    // MARK: - Drag

    func beginDrag(at point: CGPoint) {
        guard continuation != nil else { return }
        startPoint = point
        selection = CGRect(origin: point, size: .zero)
        redraw()
    }

    func updateDrag(to rawPoint: CGPoint) {
        guard let start = startPoint else { return }
        // Keep the drag inside the captured displays so the crop can never run off the frame.
        let point = bounds.isNull ? rawPoint : CGPoint(
            x: min(max(rawPoint.x, bounds.minX), bounds.maxX),
            y: min(max(rawPoint.y, bounds.minY), bounds.maxY)
        )
        let rect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        selection = rect
        redraw()
    }

    func endDrag() {
        guard let rect = selection else {
            cancel()
            return
        }
        if rect.width >= 2, rect.height >= 2 {
            finish(rect)
        } else {
            // A click or a tiny wobble is not a selection; stay open so the user can drag again.
            selection = nil
            startPoint = nil
            redraw()
        }
    }

    func cancel() {
        finish(nil)
    }

    func selection(in view: SelectionView) -> CGRect? {
        guard let selection, let frame = view.window?.frame else { return nil }
        return CGRect(
            x: selection.minX - frame.minX,
            y: selection.minY - frame.minY,
            width: selection.width,
            height: selection.height
        )
    }

    var hasSelection: Bool {
        guard let selection else { return false }
        return selection.width >= 1 && selection.height >= 1
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in views {
            view.updateSelection()
        }
        CATransaction.commit()
    }

    private func finish(_ rect: CGRect?) {
        guard !isFinishing, let continuation else { return }
        isFinishing = true
        self.continuation = nil

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for window in windows {
            window.orderOut(nil)
        }
        for window in windows {
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        views.removeAll()
        bounds = .null
        selection = nil
        startPoint = nil
        NSCursor.pop()

        if let previous = previousApp {
            if previous.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                NSApp.activate(ignoringOtherApps: true)
            } else if #available(macOS 14.0, *) {
                previous.activate()
            } else {
                previous.activate(options: [])
            }
        }

        continuation.resume(returning: rect)
        isFinishing = false
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Layer-backed overlay. The frozen frame is uploaded to the GPU once; a drag only moves a few
/// shape layers, so selection stays smooth on large Retina and multi-display setups.
final class SelectionView: NSView {
    private let image: CGImage
    private let scale: CGFloat
    private unowned let controller: AreaSelector
    private let hint: String?

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let pillLayer = CALayer()
    private let pillText = CATextLayer()
    private let hintLayer = CALayer()

    init(frame: NSRect, image: CGImage, scale: CGFloat, controller: AreaSelector, hint: String?) {
        self.image = image
        self.scale = scale
        self.controller = controller
        self.hint = hint
        super.init(frame: frame)
        // Layer-hosting: AppKit never redraws this view; only the layers below change.
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        layer = root
        wantsLayer = true
        buildLayers()
        applyContentsScale(max(1, scale))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var contentsScale: CGFloat { window?.backingScaleFactor ?? max(1, scale) }

    private func buildLayers() {
        guard let root = layer else { return }
        root.backgroundColor = NSColor.black.cgColor

        imageLayer.frame = bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        imageLayer.minificationFilter = .trilinear
        root.addSublayer(imageLayer)

        dimLayer.frame = bounds
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.06, alpha: 0.5).cgColor
        dimLayer.path = CGPath(rect: bounds, transform: nil)
        root.addSublayer(dimLayer)

        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.black.withAlphaComponent(0.5).cgColor
        outlineLayer.lineWidth = 1
        root.addSublayer(outlineLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        root.addSublayer(borderLayer)

        pillLayer.backgroundColor = NSColor.gpPill.cgColor
        pillLayer.cornerRadius = 6
        pillLayer.isHidden = true
        pillText.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        pillText.fontSize = 11
        pillText.foregroundColor = NSColor.white.cgColor
        pillText.alignmentMode = .center
        pillLayer.addSublayer(pillText)
        root.addSublayer(pillLayer)

        if let hint { buildHint(hint, in: root) }
    }

    private func buildHint(_ text: String, in root: CALayer) {
        let font = NSFont.systemFont(ofSize: 12, weight: .regular)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let frame = CGRect(x: 24, y: bounds.maxY - 24 - 32, width: ceil(size.width) + 28, height: 32)
        hintLayer.frame = frame
        hintLayer.backgroundColor = NSColor.gpPill.cgColor
        hintLayer.cornerRadius = 9
        hintLayer.borderWidth = 1
        hintLayer.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let label = CATextLayer()
        label.string = text
        label.font = font
        label.fontSize = 12
        label.foregroundColor = NSColor.gpInk.cgColor
        label.frame = CGRect(x: 14, y: (32 - ceil(size.height)) / 2 - 1, width: ceil(size.width) + 2, height: ceil(size.height) + 2)
        hintLayer.addSublayer(label)
        root.addSublayer(hintLayer)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyContentsScale(contentsScale)
    }

    private func applyContentsScale(_ s: CGFloat) {
        layer?.contentsScale = s
        pillText.contentsScale = s
        hintLayer.sublayers?.forEach { $0.contentsScale = s }
        for layer in [imageLayer, dimLayer, outlineLayer, borderLayer, pillLayer, hintLayer] as [CALayer] {
            layer.contentsScale = s
        }
    }

    func updateSelection() {
        let fullPath = CGMutablePath()
        fullPath.addRect(bounds)
        guard let local = controller.selection(in: self) else {
            dimLayer.path = fullPath
            outlineLayer.path = nil
            borderLayer.path = nil
            pillLayer.isHidden = true
            hintLayer.isHidden = false
            return
        }
        hintLayer.isHidden = true
        let clipped = local.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
            dimLayer.path = fullPath
            outlineLayer.path = nil
            borderLayer.path = nil
            pillLayer.isHidden = true
            return
        }
        // Snap to device pixels so the border stays sharp.
        let s = contentsScale
        let snapped = CGRect(
            x: (clipped.minX * s).rounded() / s,
            y: (clipped.minY * s).rounded() / s,
            width: max(1 / s, (clipped.width * s).rounded() / s),
            height: max(1 / s, (clipped.height * s).rounded() / s)
        )
        fullPath.addRect(snapped)
        dimLayer.path = fullPath
        let inner = snapped.insetBy(dx: 0.5, dy: 0.5)
        borderLayer.path = CGPath(rect: inner, transform: nil)
        outlineLayer.path = CGPath(rect: inner.insetBy(dx: -1, dy: -1), transform: nil)
        updatePill(for: local, visible: snapped)
    }

    private func updatePill(for selection: CGRect, visible: CGRect) {
        let s = contentsScale
        let width = Int((selection.width * s).rounded())
        let height = Int((selection.height * s).rounded())
        guard width >= 1, height >= 1 else {
            pillLayer.isHidden = true
            return
        }
        let text = "\(width) × \(height)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let padX: CGFloat = 8
        let padY: CGFloat = 4
        let pillSize = CGSize(width: ceil(size.width) + padX * 2, height: ceil(size.height) + padY * 2)
        var x = visible.maxX - pillSize.width - 8
        var y = visible.minY + 8
        if visible.width < pillSize.width + 16 || visible.height < pillSize.height + 16 {
            // Small selections: put the size just outside, below the bottom edge.
            x = visible.minX
            y = visible.minY - pillSize.height - 6
        }
        x = max(bounds.minX + 6, min(x, bounds.maxX - pillSize.width - 6))
        if y < bounds.minY + 6 { y = min(visible.maxY + 6, bounds.maxY - pillSize.height - 6) }
        pillText.string = text
        pillLayer.frame = CGRect(origin: CGPoint(x: x, y: y), size: pillSize)
        pillText.frame = CGRect(x: 0, y: padY - 1, width: pillSize.width, height: ceil(size.height) + 2)
        pillLayer.isHidden = false
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        controller.beginDrag(at: globalPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        controller.updateDrag(to: globalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        controller.updateDrag(to: globalPoint(for: event))
        controller.endDrag()
    }

    override func rightMouseDown(with event: NSEvent) {
        controller.cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        guard let frame = window?.frame else { return local }
        return CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)
    }
}
