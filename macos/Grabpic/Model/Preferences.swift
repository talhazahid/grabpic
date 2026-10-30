import Foundation
import Combine

/// Persisted macOS preferences. Values are logical (not Windows registry/virtual-key data)
/// and are saved quietly as they change, the way native Mac settings behave.
final class Preferences: ObservableObject {
    @Published var folder: String = Preferences.defaultFolder
    @Published var organization: Int = 0          // 0 daily, 1 ISO week, 2 monthly
    @Published var format: Int = 0                // 0 PNG, 1 JPG
    @Published var quality: Int = 100
    @Published var monitor: Int = 0               // 0 pointer display, 1 all displays
    @Published var copy: Bool = true
    @Published var watch: Bool = false
    @Published var flash: Bool = true
    @Published var shutter: Bool = true
    @Published var menuBarIcon: Bool = true
    @Published var recordSystemAudio: Bool = true
    @Published var recordMicrophone: Bool = false
    @Published var recordFrameRate: Int = 0       // 0 = 30 fps, 1 = 60 fps
    @Published var recordSize: Int = 0            // 0 = full resolution (up to 4K), 1 = 1080p
    @Published var recordCursor: Bool = true
    @Published var recordMode: Int = 0            // 0 = full screen, 1 = area
    @Published var recordFloatingControl: Bool = false
    @Published var fullScreenShortcut: ShortcutBinding? = .ctrlShift(18)
    @Published var areaShortcut: ShortcutBinding? = .ctrlShift(19)
    @Published var openCapturesShortcut: ShortcutBinding? = .ctrlShift(20)
    @Published var recordShortcut: ShortcutBinding? = .ctrlShift(23)
    @Published var settingsVersion: Int = 1

    var onSaveError: ((String) -> Void)?

    private var saveCancellable: AnyCancellable?
    private var isLoading = false

    private struct Stored: Codable {
        var folder: String?
        var organization: Int?
        var format: Int?
        var quality: Int?
        var monitor: Int?
        var copy: Bool?
        var watch: Bool?
        var flash: Bool?
        var shutter: Bool?
        var menuBarIcon: Bool?
        var recordSystemAudio: Bool?
        var recordMicrophone: Bool?
        var recordFrameRate: Int?
        var recordSize: Int?
        var recordCursor: Bool?
        var recordMode: Int?
        var recordFloatingControl: Bool?
        var recordShortcut: ShortcutBinding?
        var fullScreenShortcut: ShortcutBinding?
        var areaShortcut: ShortcutBinding?
        var openCapturesShortcut: ShortcutBinding?
        /// Action raw values the user deliberately cleared. Absent bindings alone cannot express
        /// this, because older settings files simply omit shortcuts that still use their default.
        var clearedShortcuts: [Int]?
        var settingsVersion: Int?
    }

    init() {
        isLoading = true
        load()
        if settingsVersion < 1 {
            quality = 100
            settingsVersion = 1
            saveNow()
        }
        isLoading = false
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(280), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.isLoading else { return }
                self.saveNow()
            }
    }

    static var profileDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["GRABPIC_PROFILE_DIRECTORY"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Grabpic", isDirectory: true)
    }

    static var configURL: URL {
        profileDirectory.appendingPathComponent("settings.json")
    }

    static var defaultFolder: String {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Grab Pic", isDirectory: true).path
    }

    var folderURL: URL {
        URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    var captureSettings: CaptureSettings {
        CaptureSettings(
            folder: folderURL,
            organization: organization,
            format: format,
            quality: quality
        )
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.profileDirectory, withIntermediateDirectories: true)
        let cleared = CaptureAction.allCases.filter { shortcut(for: $0) == nil }.map(\.rawValue)
        let stored = Stored(
            folder: folder,
            organization: organization,
            format: format,
            quality: quality,
            monitor: monitor,
            copy: copy,
            watch: watch,
            flash: flash,
            shutter: shutter,
            menuBarIcon: menuBarIcon,
            recordSystemAudio: recordSystemAudio,
            recordMicrophone: recordMicrophone,
            recordFrameRate: recordFrameRate,
            recordSize: recordSize,
            recordCursor: recordCursor,
            recordMode: recordMode,
            recordFloatingControl: recordFloatingControl,
            recordShortcut: recordShortcut,
            fullScreenShortcut: fullScreenShortcut,
            areaShortcut: areaShortcut,
            openCapturesShortcut: openCapturesShortcut,
            clearedShortcuts: cleared.isEmpty ? nil : cleared,
            settingsVersion: max(settingsVersion, 1)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stored)
        try data.write(to: Self.configURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.configURL) else { return }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        if let value = stored.folder, !value.isEmpty { folder = value }
        if let value = stored.organization { organization = min(max(value, 0), 2) }
        if let value = stored.format { format = min(max(value, 0), 1) }
        if let value = stored.quality { quality = min(max(value, 40), 100) }
        if let value = stored.monitor { monitor = min(max(value, 0), 1) }
        if let value = stored.copy { copy = value }
        if let value = stored.watch { watch = value }
        if let value = stored.flash { flash = value }
        if let value = stored.shutter { shutter = value }
        if let value = stored.menuBarIcon { menuBarIcon = value }
        if let value = stored.recordSystemAudio { recordSystemAudio = value }
        if let value = stored.recordMicrophone { recordMicrophone = value }
        if let value = stored.recordFrameRate { recordFrameRate = min(max(value, 0), 1) }
        if let value = stored.recordSize { recordSize = min(max(value, 0), 1) }
        if let value = stored.recordCursor { recordCursor = value }
        if let value = stored.recordMode { recordMode = min(max(value, 0), 1) }
        if let value = stored.recordFloatingControl { recordFloatingControl = value }
        let cleared = Set(stored.clearedShortcuts ?? [])
        if cleared.contains(CaptureAction.fullScreen.rawValue) {
            fullScreenShortcut = nil
        } else if let value = stored.fullScreenShortcut {
            fullScreenShortcut = value
        }
        if cleared.contains(CaptureAction.area.rawValue) {
            areaShortcut = nil
        } else if let value = stored.areaShortcut {
            areaShortcut = value
        }
        if cleared.contains(CaptureAction.openCaptures.rawValue) {
            openCapturesShortcut = nil
        } else if let value = stored.openCapturesShortcut {
            openCapturesShortcut = value
        }
        if cleared.contains(CaptureAction.record.rawValue) {
            recordShortcut = nil
        } else if let value = stored.recordShortcut {
            recordShortcut = value
        }
        if let value = stored.settingsVersion { settingsVersion = value }
    }

    private func saveNow() {
        do {
            try save()
        } catch {
            onSaveError?("Could not save preferences: \(error.localizedDescription)")
        }
    }

    func shortcut(for action: CaptureAction) -> ShortcutBinding? {
        switch action {
        case .fullScreen: return fullScreenShortcut
        case .area: return areaShortcut
        case .openCaptures: return openCapturesShortcut
        case .record: return recordShortcut
        }
    }

    func setShortcut(_ binding: ShortcutBinding?, for action: CaptureAction) {
        switch action {
        case .fullScreen: fullScreenShortcut = binding
        case .area: areaShortcut = binding
        case .openCaptures: openCapturesShortcut = binding
        case .record: recordShortcut = binding
        }
    }

    func folderName(for date: Date) -> String {
        DateFolder.name(for: date, organization: organization)
    }

    /// The dated folder a capture taken at `date` would be saved into. "Open captures" goes here so
    /// the newest grabs are one click away instead of a list of every month.
    func periodFolderURL(for date: Date = Date()) -> URL {
        folderURL.appendingPathComponent(folderName(for: date), isDirectory: true)
    }

    func examplePath(for date: Date = Date()) -> String {
        "\(folderName(for: date))/\(CaptureStore.fileName(date: date, format: format))"
    }
}

/// A value snapshot so encoding/saving can happen off the main actor.
struct CaptureSettings {
    let folder: URL
    let organization: Int
    let format: Int
    let quality: Int
}
