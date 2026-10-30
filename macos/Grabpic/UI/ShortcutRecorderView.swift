import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    let action: CaptureAction
    let current: ShortcutBinding?
    let onCancel: () -> Void
    let onSave: (ShortcutBinding) -> String?

    @State private var live: ShortcutBinding?
    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var error: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your shortcut. Your way.")
                .font(Theme.font(23))
                .foregroundStyle(Theme.ink)
            Text("Press a key or a key combination.\nModifier-only presses are ignored.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
                .lineSpacing(2)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.accent)
                Text(displayText)
                    .font(Theme.font(14))
                    .foregroundStyle(live == nil ? Color(hex: 0xB3A5FF) : Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.shortcutField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(error == nil ? Theme.accent.opacity(0.38) : Theme.warning.opacity(0.7), lineWidth: 1)
            )
            .padding(.top, 18)

            if let error {
                Text(error)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            if let current {
                Text("Current shortcut  \(current.label)")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }

            Text("Esc or Cancel keeps your current shortcut.")
                .font(Theme.font(11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Spacer()
                SoftButton(title: "Cancel", action: onCancel)
            }
            .padding(.top, 20)
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.sidebar)
        .preferredColorScheme(.dark)
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
    }

    private var displayText: String {
        if let live { return live.label }
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃ " }
        if modifiers.contains(.option) { symbols += "⌥ " }
        if modifiers.contains(.shift) { symbols += "⇧ " }
        if modifiers.contains(.command) { symbols += "⌘ " }
        if !symbols.isEmpty { return symbols + "…" }
        return "Listening for \(action.title.lowercased())…"
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .flagsChanged:
                modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // A new chord starts fresh; the previous candidate (or its message) no longer applies.
                live = nil
                error = nil
                return nil
            case .keyDown:
                if event.keyCode == 53 {
                    onCancel()
                    return nil
                }
                let key = UInt32(event.keyCode)
                if KeyNames.modifierKeys.contains(key) { return nil }
                let candidate = ShortcutBinding(
                    keyCode: key,
                    modifiers: Self.carbonModifiers(event.modifierFlags)
                )
                live = candidate
                if let message = onSave(candidate) {
                    error = message
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= ShortcutBinding.control }
        if flags.contains(.option) { value |= ShortcutBinding.option }
        if flags.contains(.shift) { value |= ShortcutBinding.shift }
        if flags.contains(.command) { value |= ShortcutBinding.command }
        return value
    }
}
