import AppKit
import QuartzCore

/// Momentary capture feedback: a brief white flash on the displays involved and the system's
/// shutter sound. Feedback is purely cosmetic, never part of the saved image, and can be turned
/// off in Settings.
@MainActor
enum CaptureFeedback {
    private static var flashes: [NSWindow] = []
    private static var shutter: NSSound?
    private static var shutterResolved = false

    static func play(flash: Bool, sound: Bool, screens: [NSScreen]) {
        if flash { showFlash(screens) }
        if sound { playShutter() }
    }

    // MARK: - Flash

    private static func showFlash(_ screens: [NSScreen]) {
        for screen in screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            // A quiet warm white, well below the intensity of a real flash.
            window.backgroundColor = NSColor(srgbRed: 1, green: 0.99, blue: 0.97, alpha: 0.2)
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.orderFrontRegardless()
            flashes.append(window)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.045
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            } completionHandler: {
                // AppKit runs animation completions on the main thread, so hop straight back into
                // the actor instead of scheduling a task for the fade-out.
                MainActor.assumeIsolated {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.19
                        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                        window.animator().alphaValue = 0
                    } completionHandler: {
                        MainActor.assumeIsolated {
                            window.orderOut(nil)
                            window.close()
                            flashes.removeAll { $0 === window }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shutter

    private static func playShutter() {
        guard let shutter = shutterSound() else { return }
        if shutter.isPlaying { shutter.stop() }
        shutter.play()
    }

    private static func shutterSound() -> NSSound? {
        if shutterResolved { return shutter }
        shutterResolved = true

        // The system's own camera shutter, with a screenshot click and a bundled fallback for
        // macOS releases that move the resource.
        let candidates = [
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        ]
        for path in candidates {
            if let sound = NSSound(contentsOfFile: path, byReference: true) {
                sound.volume = 0.55
                shutter = sound
                return sound
            }
        }
        let fallback = NSSound(named: NSSound.Name("Tink"))
        fallback?.volume = 0.5
        shutter = fallback
        return fallback
    }
}
