import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupHeader(title: "Screenshot")
            HStack(spacing: 14) {
                ActionCard(
                    symbol: "display",
                    title: "Grab full screen",
                    caption: "The whole picture, in one click.",
                    shortcut: state.shortcutLabel(for: .fullScreen),
                    minHeight: 150
                ) {
                    state.capture(.fullScreen)
                }
                ActionCard(
                    symbol: "rectangle.dashed",
                    title: "Grab an area",
                    caption: "Only what matters. Nothing extra.",
                    shortcut: state.shortcutLabel(for: .area),
                    minHeight: 150
                ) {
                    state.capture(.area)
                }
            }
            .padding(.bottom, 20)

            GroupHeader(title: "Recording") {
                HStack(spacing: 8) {
                    ChipToggle(
                        onSymbol: "speaker.wave.2",
                        offSymbol: "speaker.slash",
                        title: "Sound",
                        isOn: $preferences.recordSystemAudio
                    )
                    ChipToggle(
                        onSymbol: "mic",
                        offSymbol: "mic.slash",
                        title: "Mic",
                        isOn: $preferences.recordMicrophone
                    )
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 14) {
                    recordCard(mode: 0)
                    recordCard(mode: 1)
                }
            }
            .padding(.bottom, 24)

            HStack(alignment: .center) {
                Text("Your latest capture")
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.ink)
                Spacer()
                LinkButton(title: "Open folder ↗", size: 12) {
                    state.openFolder()
                }
            }
            .padding(.bottom, 12)

            LatestCard()
        }
    }

    /// Recording cards start right away with the Sound and Mic choices above. While a recording
    /// runs, the card that started it becomes the stop control.
    @ViewBuilder
    private func recordCard(mode: Int) -> some View {
        let isArea = mode == 1
        let isThisRecording = state.isRecording && state.activeRecordingMode == mode
        ActionCard(
            symbol: isThisRecording ? "stop.circle" : (isArea ? "rectangle.dashed.badge.record" : "record.circle"),
            title: isThisRecording ? "Stop recording" : (isArea ? "Record an area" : "Record full screen"),
            caption: isThisRecording
                ? "Recording · \(state.recordingElapsed)"
                : (isArea ? "Drag to choose what to record." : "Your whole display, as video."),
            shortcut: isThisRecording ? "Click to stop" : (isArea ? "Click, then drag" : "Click to start"),
            minHeight: 150,
            tint: Color(hex: 0xEF6A6E),
            active: isThisRecording,
            disabled: state.isRecording && !isThisRecording
        ) {
            if isThisRecording {
                state.stopRecording()
            } else {
                state.startRecording(isArea ? .area : .fullScreen)
            }
        }
    }
}

private struct LatestCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 16) {
                Button {
                    state.openPreview()
                } label: {
                    Thumbnail(image: state.latest?.image)
                        .overlay(alignment: .bottomTrailing) {
                            if state.latest != nil {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 8, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .padding(4)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                                    .padding(4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(state.latest == nil)
                .help(state.latest == nil ? "No capture yet" : "Preview the latest capture")
                .accessibilityLabel("Preview the latest capture")

                VStack(alignment: .leading, spacing: 6) {
                    Text(state.latest?.name ?? "Your next capture starts here")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(state.latest?.detail ?? "Take a screenshot to see it here.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                SoftButton(title: "Reveal", disabled: state.latest == nil) {
                    state.revealLatest()
                }
            }
        }
    }
}


private struct GroupHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            SectionLabel(text: title.uppercased())
            Spacer(minLength: 12)
            trailing
        }
        .padding(.leading, 2)
        .padding(.bottom, 10)
    }
}

extension GroupHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}
