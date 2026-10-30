import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            VStack(spacing: 0) {
                header
                ScrollView(.vertical) {
                    content
                        .padding(.horizontal, 36)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
        .sheet(item: $state.preview) { capture in
            PreviewSheet(capture: capture)
                .environmentObject(state)
                .environmentObject(preferences)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.font(28))
                .foregroundStyle(Theme.ink)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 38)
        .padding(.bottom, 26)
    }

    @ViewBuilder
    private var content: some View {
        switch state.route {
        case .capture:
            CaptureView()
        case .settings:
            SettingsView()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: 0x2B2C37))
                .frame(height: 1)
            HStack {
                Text(state.status)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 36)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .padding(.top, 20)
        .background(Theme.canvas)
    }

    private var title: String {
        switch state.route {
        case .capture: return "Screenshots and recordings, one shortcut away."
        case .settings: return "Make it yours."
        }
    }

    private var subtitle: String {
        switch state.route {
        case .capture: return ""
        case .settings: return "Shortcuts, saving, and how captures behave. Changes save as you go."
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 34)
                Text("Grab Pic")
                    .font(Theme.font(21))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 10)
            .padding(.top, 52)
            .padding(.bottom, 34)

            VStack(spacing: 6) {
                NavButton(
                    title: "Capture",
                    symbol: "camera",
                    selected: state.route == .capture
                ) {
                    state.route = .capture
                }
                NavButton(
                    title: "Settings",
                    symbol: "gearshape",
                    selected: state.route == .settings
                ) {
                    state.route = .settings
                }
            }

            Spacer(minLength: 24)

            DeveloperCredit()
                .padding(.leading, 10)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .frame(width: Theme.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(hex: 0x2B2C37))
                .frame(width: 1)
        }
    }
}


/// "Developed by NXT Labs" at the bottom of the sidebar; opens nxtlabs.com.
private struct DeveloperCredit: View {
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: "https://nxtlabs.com") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Text("Developed by")
                    .foregroundStyle(Theme.muted)
                Text("NXT Labs")
                    .foregroundStyle(hovering ? Theme.accent : Theme.ink)
                    .underline(hovering)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(hovering ? Theme.accent : Theme.muted)
            }
            .font(Theme.font(12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("nxtlabs.com")
        .accessibilityLabel("Developed by NXT Labs. Opens nxtlabs.com")
    }
}
