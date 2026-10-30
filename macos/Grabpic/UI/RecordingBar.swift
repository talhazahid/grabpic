import AppKit
import SwiftUI

/// A small floating bar shown before a recording starts, in the spirit of the macOS screenshot
/// toolbar: choose full screen or an area, sound on or off, microphone on or off, then Record.
/// Choices are remembered for next time.
@MainActor
final class RecordingBarController {
    private var panel: RecordingPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func show(state: AppState) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let record: () -> Void = { [weak self, weak state] in
            self?.close()
            guard let state else { return }
            state.startRecording(state.preferences.recordMode == 1 ? .area : .fullScreen)
        }
        let root = RecordingBar(
            onRecord: record,
            onCancel: { [weak self] in self?.close() }
        )
        .environmentObject(state)
        .environmentObject(state.preferences)

        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let screen = CaptureService.shared.screenUnderPointer() ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + 72,
            width: size.width,
            height: size.height
        )
        let panel = RecordingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            switch event.keyCode {
            case 53: // Esc
                self.close()
                return nil
            case 36, 76: // Return, Enter
                record()
                return nil
            default:
                return event
            }
        }
    }

    func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct RecordingBar: View {
    @EnvironmentObject private var preferences: Preferences
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            BarChoice(symbol: "display", title: "Full screen", selected: preferences.recordMode == 0) {
                preferences.recordMode = 0
            }
            BarChoice(symbol: "rectangle.dashed", title: "Area", selected: preferences.recordMode == 1) {
                preferences.recordMode = 1
            }

            barDivider

            BarToggle(
                onSymbol: "speaker.wave.2",
                offSymbol: "speaker.slash",
                title: "Sound",
                isOn: $preferences.recordSystemAudio
            )
            BarToggle(
                onSymbol: "mic",
                offSymbol: "mic.slash",
                title: "Mic",
                isOn: $preferences.recordMicrophone
            )

            barDivider

            Button(action: onRecord) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: 0xEF5257))
                        .frame(width: 10, height: 10)
                    Text("Record")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(Color(hex: 0x3A2A33))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Color(hex: 0xEF5257).opacity(0.45), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Start recording (Return)")

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
            .accessibilityLabel("Cancel")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.borderStrong, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .fixedSize()
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }
}

private struct BarChoice: View {
    let symbol: String
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                Text(title)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(selected ? Theme.selection : (hovering ? Theme.cardHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BarToggle: View {
    let onSymbol: String
    let offSymbol: String
    let title: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? onSymbol : offSymbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isOn ? Theme.accent : Theme.muted)
                    .frame(width: 16)
                Text(title)
                    .font(Theme.font(13))
                    .foregroundStyle(isOn ? Theme.ink : Theme.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(hovering ? Theme.cardHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isOn ? "\(title) on" : "\(title) off")
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
