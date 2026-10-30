import Foundation

/// A macOS key combination. Carbon virtual key codes and Carbon modifier masks are
/// stored so registrations survive relaunches; Windows virtual-key integers are never reused.
struct ShortcutBinding: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let command = UInt32(256)
    static let shift = UInt32(512)
    static let option = UInt32(2048)
    static let control = UInt32(4096)

    static func ctrlShift(_ keyCode: UInt32) -> ShortcutBinding {
        ShortcutBinding(keyCode: keyCode, modifiers: control | shift)
    }

    var label: String {
        var parts: [String] = []
        if modifiers & ShortcutBinding.control != 0 { parts.append("⌃") }
        if modifiers & ShortcutBinding.option != 0 { parts.append("⌥") }
        if modifiers & ShortcutBinding.shift != 0 { parts.append("⇧") }
        if modifiers & ShortcutBinding.command != 0 { parts.append("⌘") }
        parts.append(KeyNames.name(for: keyCode))
        return parts.joined()
    }

    var hasModifier: Bool {
        modifiers & (ShortcutBinding.command | ShortcutBinding.shift | ShortcutBinding.option | ShortcutBinding.control) != 0
    }

    var isFunctionKey: Bool {
        KeyNames.functionKeys.contains(keyCode)
    }

    /// Returns a user-facing validation message, or nil when the combination is acceptable.
    func validationError() -> String? {
        if KeyNames.modifierKeys.contains(keyCode) {
            return "Add a regular key to the modifier combination."
        }
        if !hasModifier && !isFunctionKey {
            return "Add a modifier key such as ⌃, ⌥, or ⌘."
        }
        if ShortcutBinding.reserved.contains(self) {
            return "macOS reserves that combination. Choose another."
        }
        return nil
    }

    /// Combinations macOS owns or that should never be captured globally.
    static let reserved: Set<ShortcutBinding> = [
        ShortcutBinding(keyCode: 49, modifiers: command),                                  // ⌘Space
        ShortcutBinding(keyCode: 48, modifiers: command),                                  // ⌘Tab
        ShortcutBinding(keyCode: 50, modifiers: command),                                  // ⌘`
        ShortcutBinding(keyCode: 12, modifiers: command),                                  // ⌘Q
        ShortcutBinding(keyCode: 12, modifiers: command | shift),                          // ⇧⌘Q
        ShortcutBinding(keyCode: 12, modifiers: command | control),                        // ⌃⌘Q
        ShortcutBinding(keyCode: 20, modifiers: command | shift),                          // ⇧⌘3
        ShortcutBinding(keyCode: 21, modifiers: command | shift),                          // ⇧⌘4
        ShortcutBinding(keyCode: 23, modifiers: command | shift),                          // ⇧⌘5
        ShortcutBinding(keyCode: 22, modifiers: command | shift),                          // ⇧⌘6
        ShortcutBinding(keyCode: 53, modifiers: command | option),                         // ⌥⌘Esc
        ShortcutBinding(keyCode: 53, modifiers: 0),                                        // Esc
        ShortcutBinding(keyCode: 36, modifiers: 0),                                        // Return
        ShortcutBinding(keyCode: 48, modifiers: 0)                                         // Tab
    ]
}

enum KeyNames {
    static let modifierKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static let functionKeys: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106,
        64, 79, 80, 90
    ]

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 53: "Esc",
        64: "F17", 65: ".", 67: "*", 69: "+", 71: "Clear", 75: "/", 76: "Enter", 78: "-",
        79: "F18", 80: "F19", 81: "=", 82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
        87: "5", 88: "6", 89: "7", 90: "F20", 91: "8", 92: "9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
