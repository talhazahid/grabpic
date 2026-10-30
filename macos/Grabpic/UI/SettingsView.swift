import SwiftUI
import AppKit

/// Settings use one structure throughout: a card per topic with an icon, a title and one line of
/// purpose, then rows. Each row has a title and one line of help on the left and a single control
/// on the right, separated by hairlines. Changes save immediately.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(
                "Permission",
                subtitle: "What macOS lets Grab Pic see.",
                symbol: "lock.shield"
            ) { PermissionGroup() }
            SettingsSection(
                "Shortcuts",
                subtitle: "Click a shortcut, then press the new keys.",
                symbol: "command",
                trailing: AnyView(SoftButton(title: "Restore defaults", height: 30) { state.resetShortcuts() })
            ) { ShortcutsGroup() }
            SettingsSection(
                "Saving",
                subtitle: "Where captures go and how they are named.",
                symbol: "folder"
            ) { SavingGroup() }
            SettingsSection(
                "After a capture",
                subtitle: "What happens the moment you grab.",
                symbol: "camera.aperture"
            ) { AfterCaptureGroup() }
            SettingsSection(
                "Screen recording",
                subtitle: "Defaults for new recordings. Saved as MP4.",
                symbol: "record.circle"
            ) { RecordingGroup() }
            SettingsSection(
                "General",
                subtitle: "Startup and clipboard.",
                symbol: "gearshape"
            ) { GeneralGroup() }
            SettingsSection(
                "Menu bar",
                subtitle: "Grab Pic lives here when the window is closed.",
                symbol: "menubar.rectangle"
            ) { MenuBarGroup() }
        }
        .padding(.bottom, 8)
        .sheet(item: $state.recorderAction) { action in
            ShortcutRecorderView(
                action: action,
                current: preferences.shortcut(for: action),
                onCancel: { state.recorderAction = nil },
                onSave: { binding in
                    if let error = state.setShortcut(binding, for: action) {
                        return error
                    }
                    state.recorderAction = nil
                    return nil
                }
            )
            .environmentObject(state)
            .environmentObject(preferences)
        }
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let trailing: AnyView?
    @ViewBuilder var content: Content

    init(
        _ title: String,
        subtitle: String,
        symbol: String,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                        .overlay(
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Theme.accent)
                        )
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Theme.font(15))
                            .foregroundStyle(Theme.ink)
                        Text(subtitle)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 12)
                    if let trailing { trailing }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// One settings row. `divider` draws the hairline above it, inset to the text column.
private struct Row<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var captionColor: Color = Theme.muted
    var divider: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            if divider {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.font(13.5))
                        .foregroundStyle(Theme.ink)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(Theme.font(12))
                            .foregroundStyle(captionColor)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(minHeight: 60)
        }
    }
}

private struct SwitchRow: View {
    let title: String
    var caption: String? = nil
    var divider: Bool = true
    @Binding var isOn: Bool

    var body: some View {
        Row(title: title, caption: caption, divider: divider) {
            SwitchToggle(isOn: $isOn, label: title)
        }
    }
}

// MARK: - Permission

private struct PermissionGroup: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Row(
            title: "Screen Recording",
            caption: caption,
            divider: false
        ) {
            HStack(spacing: 10) {
                StatusPill(
                    text: state.screenPermission ? "Allowed" : "Not allowed",
                    color: state.screenPermission ? Theme.success : Theme.warning
                )
                if !state.screenPermission {
                    SoftButton(title: state.permissionRequestInFlight ? "Open System Settings" : "Allow Screen Recording") {
                        state.allowScreenRecording()
                    }
                }
            }
        }
    }

    private var caption: String {
        if state.screenPermission {
            return "Screenshots, recordings, and their sound. Everything stays on this Mac."
        }
        if state.permissionRequestInFlight {
            return "Switch on Grab Pic in System Settings, then choose Quit & Reopen."
        }
        return "One permission for screenshots, recordings, and their sound. Allow it once."
    }
}

// MARK: - Shortcuts

private struct ShortcutsGroup: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ForEach(Array(CaptureAction.allCases.enumerated()), id: \.element.id) { index, action in
            Row(title: action.settingsTitle, caption: action.caption, divider: index > 0) {
                HStack(spacing: 8) {
                    ShortcutField(title: state.shortcutLabel(for: action), minWidth: 150) {
                        state.recorderAction = action
                    }
                    SoftButton(
                        title: "Clear",
                        disabled: state.preferences.shortcut(for: action) == nil
                    ) {
                        state.setShortcut(nil, for: action)
                    }
                }
            }
        }

    }
}

// MARK: - Saving

private struct SavingGroup: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Row(
            title: "Save to",
            caption: (preferences.folder as NSString).abbreviatingWithTildeInPath,
            captionColor: Theme.accent,
            divider: false
        ) {
            SoftButton(title: "Change…") {
                state.chooseFolder()
            }
        }
        .help(preferences.folder)

        Row(
            title: "Group into folders",
            caption: "e.g. \(preferences.examplePath())"
        ) {
            SelectControl(
                options: ["By day", "By week", "By month"],
                selection: $preferences.organization
            )
        }

        Row(
            title: "Format",
            caption: preferences.format == 0
                ? "PNG keeps every pixel. Best for text and UI."
                : "JPG makes smaller files. Best for photos."
        ) {
            SelectControl(
                options: ["PNG", "JPG"],
                selection: $preferences.format
            )
        }

        if preferences.format == 1 {
            Row(
                title: "JPG quality",
                caption: "Higher is sharper and larger. Even 100 is slightly lossy."
            ) {
                QualitySlider(value: $preferences.quality, enabled: true)
            }
        }
    }
}

// MARK: - After a capture

private struct AfterCaptureGroup: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Row(
            title: "Full-screen grabs",
            caption: preferences.monitor == 0
                ? "Only the display your pointer is on."
                : "Every display, joined into one image.",
            divider: false
        ) {
            SelectControl(
                options: ["Current display", "All displays"],
                selection: $preferences.monitor,
                width: 170
            )
        }

        SwitchRow(
            title: "Copy to clipboard",
            caption: "Ready to paste the moment you grab.",
            isOn: $preferences.copy
        )
        SwitchRow(
            title: "Flash",
            caption: "A soft flash on the screen you captured.",
            isOn: $preferences.flash
        )
        SwitchRow(
            title: "Shutter sound",
            caption: "The Mac's camera shutter.",
            isOn: $preferences.shutter
        )
    }
}

// MARK: - Recording

private struct RecordingGroup: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        SwitchRow(
            title: "System audio",
            caption: "Sound playing on this Mac: videos, calls, apps.",
            divider: false,
            isOn: $preferences.recordSystemAudio
        )
        SwitchRow(
            title: "Microphone",
            caption: "Your voice, mixed with the Mac's sound. macOS asks once.",
            isOn: $preferences.recordMicrophone
        )
        SwitchRow(
            title: "Floating stop button",
            caption: "A small Stop control at the top of the screen. The menu bar timer always stops recording.",
            isOn: $preferences.recordFloatingControl
        )
        SwitchRow(
            title: "Show pointer",
            caption: "Include the mouse pointer in the video.",
            isOn: $preferences.recordCursor
        )
        Row(
            title: "Video size",
            caption: preferences.recordSize == 0
                ? "Sharp, full Retina detail, up to 4K."
                : "Smaller files that upload and stream fast."
        ) {
            SelectControl(
                options: ["Full resolution", "1080p"],
                selection: $preferences.recordSize
            )
        }
        Row(
            title: "Frame rate",
            caption: "Saved as MP4 (H.264 + AAC), ready for the web."
        ) {
            SelectControl(
                options: ["30 fps", "60 fps"],
                selection: $preferences.recordFrameRate
            )
        }
    }
}

// MARK: - General

private struct GeneralGroup: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        SwitchRow(
            title: "Open at login",
            caption: state.loginItemNote?.isEmpty == false
                ? state.loginItemNote
                : "Starts in the menu bar when you sign in.",
            divider: false,
            isOn: Binding(
                get: { state.loginItemEnabled },
                set: { state.setLoginItem($0) }
            )
        )
        SwitchRow(
            title: "Save copied images",
            caption: "Images you copy in other apps are saved too, while Grab Pic is running.",
            isOn: $preferences.watch
        )
    }
}

// MARK: - Menu bar

private struct MenuBarGroup: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        SwitchRow(
            title: "Show icon in the menu bar",
            caption: "Turn it off to stay out of the way. Open Grab Pic from Finder to come back here.",
            divider: false,
            isOn: $preferences.menuBarIcon
        )
    }
}
