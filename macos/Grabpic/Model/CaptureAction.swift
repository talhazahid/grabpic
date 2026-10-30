import Foundation

enum CaptureAction: Int, CaseIterable, Identifiable {
    case fullScreen = 1
    case area = 2
    case openCaptures = 3
    case record = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fullScreen: return "Full screen"
        case .area: return "Grab area"
        case .openCaptures: return "Open captures"
        case .record: return "Record screen"
        }
    }

    var caption: String {
        switch self {
        case .fullScreen: return "Your current display, or all of them."
        case .area: return "Drag to select just the part you need."
        case .openCaptures: return "Jump straight to your latest captures."
        case .record: return "Opens the recording bar. Press again to stop."
        }
    }

    var settingsTitle: String {
        switch self {
        case .fullScreen: return "Grab full screen"
        case .area: return "Grab an area"
        case .openCaptures: return "Open captures"
        case .record: return "Record screen"
        }
    }

    var menuTitle: String {
        switch self {
        case .fullScreen: return "Grab Full Screen"
        case .area: return "Grab Area"
        case .openCaptures: return "Open Captures"
        case .record: return "Record Screen"
        }
    }

    var defaultBinding: ShortcutBinding {
        switch self {
        case .fullScreen: return .ctrlShift(18)
        case .area: return .ctrlShift(19)
        case .openCaptures: return .ctrlShift(20)
        case .record: return .ctrlShift(23)   // ⌃⇧5
        }
    }
}
