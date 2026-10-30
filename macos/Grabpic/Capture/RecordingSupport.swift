import AppKit
import AVFoundation
import SwiftUI

/// Reads what the latest-capture card needs from a finished MP4: a poster frame, the size,
/// the length, and the file size.
enum VideoInfo {
    static func load(_ url: URL) async -> LatestCapture? {
        let asset = AVURLAsset(url: url)
        var width = 0
        var height = 0
        var seconds = 0.0
        if let duration = try? await asset.load(.duration) {
            seconds = duration.seconds.isFinite ? duration.seconds : 0
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize) {
            width = Int(abs(size.width).rounded())
            height = Int(abs(size.height).rounded())
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        var poster: NSImage?
        let at = CMTime(seconds: min(0.5, seconds / 2), preferredTimescale: 600)
        if let frame = try? await generator.image(at: at).image {
            poster = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        }

        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = bytes >= 1_048_576
            ? String(format: "%.1f MB", Double(bytes) / 1_048_576)
            : "\(bytes / 1024) KB"
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let detail = "Video · \(width) × \(height) · \(AppState.duration(seconds)) · \(size) · \(modified.formatted(date: .numeric, time: .shortened))"
        return LatestCapture(
            url: url,
            name: url.lastPathComponent,
            detail: detail,
            image: poster,
            pixelWidth: width,
            pixelHeight: height
        )
    }
}

/// A thin outline around the area being recorded. Grab Pic excludes its own windows from the
/// recording, so the outline guides the user without appearing in the video.
@MainActor
final class RecordingBorder {
    private let window: NSWindow

    init(rect: CGRect, screen: NSScreen) {
        let frame = rect.insetBy(dx: -3, dy: -3).intersection(screen.frame)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.setFrame(frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.sharingType = .none

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let border = CAShapeLayer()
        border.frame = view.bounds
        border.path = CGPath(rect: view.bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        border.fillColor = nil
        border.strokeColor = NSColor(srgbRed: 0.93, green: 0.33, blue: 0.36, alpha: 0.95).cgColor
        border.lineWidth = 2
        border.lineDashPattern = [8, 5]
        view.layer?.addSublayer(border)
        window.contentView = view
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

/// A small floating control shown while recording: a pulsing red dot, the running time, and a
/// Stop button. It sits just below the menu bar on the recorded display, can be dragged, and is
/// never part of the video (Grab Pic excludes its own windows). Unlike a menu bar icon, it cannot
/// be hidden behind the notch.
@MainActor
final class RecordingHUD {
    private let panel: NSPanel

    init(screen: NSScreen, state: AppState) {
        let hosting = FirstMouseHostingView(rootView: RecordingHUDView(onStop: { [weak state] in
            state?.stopRecording()
        }).environmentObject(state))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let frame = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 10,
            width: size.width,
            height: size.height
        )
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        // Never part of a screenshot or recording.
        panel.sharingType = .none
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Lets the first click on a background panel press the button instead of only focusing it.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RecordingHUDView: View {
    @EnvironmentObject private var state: AppState
    let onStop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xEF5257).opacity(0.35))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse ? 1.0 : 0.55)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .fill(Color(hex: 0xEF5257))
                    .frame(width: 9, height: 9)
            }
            .frame(width: 18, height: 18)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(state.isStoppingRecording ? "Saving…" : state.recordingElapsed)
                    .font(.system(size: 13, weight: .regular).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 44, alignment: .leading)
            }

            HStack(spacing: 6) {
                if state.recordingSystemAudio {
                    Image(systemName: "speaker.wave.2")
                        .help("Recording the Mac's sound")
                }
                if let mic = state.recordingMicrophone {
                    Image(systemName: mic ? "mic.fill" : "mic.slash")
                        .foregroundStyle(mic ? Theme.ink : Color(hex: 0xEF6A6E))
                        .help(mic ? "Recording the microphone" : "Microphone unavailable: check System Settings → Privacy & Security → Microphone")
                }
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Theme.muted)

            Button(action: onStop) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                    Text("Stop")
                        .font(Theme.font(13))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule(style: .continuous).fill(Color(hex: 0xE5484D)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(state.isStoppingRecording)
            .help("Stop and save the recording")
            .accessibilityLabel("Stop recording")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(Capsule(style: .continuous).fill(Theme.card.opacity(0.96)))
        .overlay(Capsule(style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
        .preferredColorScheme(.dark)
        .fixedSize()
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
