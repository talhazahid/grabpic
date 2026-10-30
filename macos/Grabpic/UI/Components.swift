import SwiftUI
import AppKit

// MARK: - Surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.vertical, 18)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.uppercase(10))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.uppercase(10))
            .tracking(1.4)
            .foregroundStyle(Theme.accent)
    }
}

// MARK: - Buttons

struct SoftButton: View {
    let title: String
    var minWidth: CGFloat? = nil
    var height: CGFloat = 34
    var disabled: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(13))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: minWidth, minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(hovering ? Theme.cardHover : Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(hovering ? Color(hex: 0x454759) : Theme.borderStrong, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 && !disabled }
        .accessibilityLabel(title)
    }
}

struct ShortcutField: View {
    let title: String
    var minWidth: CGFloat = 165
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(12))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: minWidth, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(hovering ? Color(hex: 0x332F47) : Theme.shortcutField)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(hovering ? Theme.accent.opacity(0.5) : Theme.borderStrong, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

struct LinkButton: View {
    let title: String
    var size: CGFloat = 12
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(size))
                .foregroundStyle(hovering ? Theme.accent : Theme.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

struct NavButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(selected ? Theme.selection : (hovering ? Color.white.opacity(0.035) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ActionCard: View {
    let symbol: String
    let title: String
    let caption: String
    let shortcut: String
    var minHeight: CGFloat = 188
    var tint: Color = Theme.accent
    var active: Bool = false
    var disabled: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(tint)
                Spacer(minLength: 18)
                Text(title)
                    .font(Theme.font(19))
                    .foregroundStyle(Theme.ink)
                Text(caption)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                Spacer(minLength: 16)
                Text(shortcut)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(active ? tint.opacity(0.10) : (hovering ? Theme.cardHover : Theme.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(active ? tint.opacity(0.55) : (hovering ? tint.opacity(0.38) : Theme.border), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 && !disabled }
        .accessibilityLabel(title)
        .accessibilityHint(caption)
    }
}

// MARK: - Controls

struct CheckToggle: View {
    let title: String
    @Binding var isOn: Bool
    var caption: String? = nil

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Theme.accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isOn ? Theme.accent : Theme.muted.opacity(0.55), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(Color.white)
                            .opacity(isOn ? 1 : 0)
                    )
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.ink)
                    if let caption {
                        Text(caption)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A compact on/off switch in the accent colour, matching the dark control set.
struct SwitchToggle: View {
    @Binding var isOn: Bool
    var label: String = ""
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.accent : (hovering ? Color(hex: 0x3A3B4B) : Color(hex: 0x33343F)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isOn ? Color.clear : Theme.borderStrong, lineWidth: 1)
                    )
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .frame(width: 36, height: 20)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

struct SelectControl: View {
    let options: [String]
    @Binding var selection: Int
    var width: CGFloat = 170
    var disabled: Bool = false
    @State private var hovering = false

    var body: some View {
        Button {
            PopupMenuPresenter.show(options: options, selected: selection) { index in
                selection = index
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.indices.contains(selection) ? options[selection] : "")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(hovering ? Theme.cardHover : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .stroke(Theme.borderStrong, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 && !disabled }
        .accessibilityLabel(options.indices.contains(selection) ? options[selection] : "")
        .accessibilityHint("Opens a menu to choose an option")
    }
}

enum PopupMenuPresenter {
    private final class Handler: NSObject {
        let callback: (Int) -> Void
        init(callback: @escaping (Int) -> Void) {
            self.callback = callback
        }

        @objc func choose(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int else { return }
            DispatchQueue.main.async { [callback] in callback(index) }
        }
    }

    @MainActor
    static func show(options: [String], selected: Int, onSelect: @escaping (Int) -> Void) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let content = window.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let handler = Handler(callback: onSelect)
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(title: option, action: #selector(Handler.choose(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = index
            item.state = index == selected ? .on : .off
            menu.addItem(item)
        }

        var point = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        point.x = max(4, min(point.x, content.bounds.width - 8))
        point.y = max(4, point.y - 4)
        menu.popUp(positioning: nil, at: point, in: content)
        _ = handler
    }
}


struct QualitySlider: View {
    @Binding var value: Int
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: 40...100,
                step: 1
            )
            .tint(Theme.accent)
            .frame(width: 140)
            Text("\(value)")
                .font(Theme.font(12))
                .foregroundStyle(Theme.muted)
                .frame(width: 26, alignment: .leading)
                .monospacedDigit()
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel("JPG quality")
    }
}

// MARK: - Rows

struct SettingRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            leading
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct RowTitle: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.font(14))
                .foregroundStyle(Theme.ink)
            if let caption {
                Text(caption)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Detail pieces

struct BrandMark: View {
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0xB2A5FF), Color(hex: 0x9385F2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Image(systemName: "camera")
                    .font(.system(size: size * 0.5, weight: .regular))
                    .foregroundStyle(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: Theme.accent.opacity(0.16), radius: 8, y: 2)
            .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.font(11))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }
}

struct Thumbnail: View {
    let image: NSImage?
    var width: CGFloat = 84
    var height: CGFloat = 60

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.thumb)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.muted.opacity(0.7))
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}


/// A small on/off chip with an icon, used for quick recording choices.
struct ChipToggle: View {
    let onSymbol: String
    let offSymbol: String
    let title: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? onSymbol : offSymbol)
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 14)
                Text(title)
                    .font(Theme.font(12))
            }
            .foregroundStyle(isOn ? Theme.ink : Theme.muted)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.selection : (hovering ? Theme.cardHover : Theme.card))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isOn ? Theme.accent.opacity(0.45) : Theme.borderStrong, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isOn ? "\(title) on" : "\(title) off")
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
