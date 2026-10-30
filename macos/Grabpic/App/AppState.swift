import AppKit
import CoreGraphics
import SwiftUI
import Combine
import AVFoundation

struct LatestCapture: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let detail: String
    let image: NSImage?
    let pixelWidth: Int
    let pixelHeight: Int

    var path: String { url.path }
    var isVideo: Bool { url.pathExtension.lowercased() == "mp4" }

    static func == (lhs: LatestCapture, rhs: LatestCapture) -> Bool {
        lhs.url == rhs.url && lhs.detail == rhs.detail && lhs.id == rhs.id
    }
}

enum AppRoute {
    case capture
    case settings
}

@MainActor
final class AppState: ObservableObject {
    enum CaptureKind {
        case fullScreen
        case area
    }

    let preferences: Preferences

    @Published var route: AppRoute = .capture
    @Published var status: String = "Ready when you are."
    @Published var latest: LatestCapture?
    @Published var preview: LatestCapture?
    @Published var isCapturing = false
    @Published private(set) var screenPermission: Bool
    @Published var loginItemEnabled: Bool
    @Published var loginItemNote: String?
    @Published var recorderAction: CaptureAction?
    @Published private(set) var isRecording = false
    @Published private(set) var isStoppingRecording = false
    @Published private(set) var recordingStartedAt: Date?
    /// 0 = full screen, 1 = area, while a recording runs.
    @Published private(set) var activeRecordingMode: Int?
    /// While recording: nil = microphone not requested, true = recording it, false = requested but unavailable.
    @Published private(set) var recordingMicrophone: Bool?
    @Published private(set) var recordingSystemAudio = false

    private var screenRecorder: ScreenRecorder?
    private var recordingFinalURL: URL?
    private var recordingBorder: RecordingBorder?
    private let recordingBar = RecordingBarController()
    private var recordingHUD: RecordingHUD?

    private let captureService = CaptureService.shared
    private let shortcuts = ShortcutService.shared
    private let areaSelector = AreaSelector.shared
    private let watcher = ClipboardWatcher()
    private var windowController: MainWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var latestRequest = 0
    private var activationObserver: NSObjectProtocol?
    private let servicesEnabled: Bool

    init(enableServices: Bool = true) {
        let preferences = Preferences()
        self.preferences = preferences
        self.servicesEnabled = enableServices
        self.screenPermission = enableServices ? CaptureService.shared.hasScreenPermission : true
        self.loginItemEnabled = enableServices ? LoginItemService.isEnabled : false
        self.loginItemNote = enableServices ? LoginItemService.explanation : nil

        preferences.onSaveError = { [weak self] message in
            self?.status = message
        }

        if enableServices {
            shortcuts.onInvoke = { [weak self] action in
                self?.perform(action: action)
            }
            watcher.onImage = { [weak self] image in
                self?.saveClipboardImage(image)
            }
            watcher.shouldPause = { [weak self] in
                self?.isCapturing ?? true
            }
            watcher.isEnabled = preferences.watch

            preferences.$watch
                .removeDuplicates()
                .sink { [weak self] enabled in
                    self?.watcher.isEnabled = enabled
                }
                .store(in: &cancellables)

            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshSystemState() }
            }

            registerConfiguredShortcuts()
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Lifecycle

    func launch(showWindow: Bool) {
        refreshSystemState()
        if showWindow {
            showApp()
        } else {
            NSApp.setActivationPolicy(.accessory)
            status = "Ready when you are."
        }
    }

    func refreshSystemState() {
        screenPermission = captureService.hasScreenPermission
        loginItemEnabled = LoginItemService.isEnabled
        loginItemNote = LoginItemService.explanation
        // No ScreenCaptureKit probe here: asking for content without access makes macOS show its
        // permission prompt, and this runs every time the app becomes active.
    }

    func showApp(route: AppRoute? = nil) {
        if let route { self.route = route }
        NSApp.setActivationPolicy(.regular)

        if windowController == nil {
            let root = RootView()
                .environmentObject(self)
                .environmentObject(preferences)
            let controller = MainWindowController(rootView: root)
            controller.onHide = { [weak self] in
                self?.mainWindowDidHide()
            }
            windowController = controller
        }
        windowController?.present()
        NSApp.activate(ignoringOtherApps: true)
        refreshSystemState()
        Task { await loadLatest(force: false) }
    }

    func showSettings() {
        showApp(route: .settings)
    }

    func mainWindowClosed() {
        // Cmd+Q or termination path; no extra window policy needed.
    }

    private func mainWindowDidHide() {
        NSApp.setActivationPolicy(.accessory)
        status = "Still running in the menu bar."
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Commands

    func perform(action: CaptureAction) {
        switch action {
        case .fullScreen:
            capture(.fullScreen)
        case .area:
            capture(.area)
        case .openCaptures:
            openFolder()
        case .record:
            toggleRecording()
        }
    }

    func capture(_ kind: CaptureKind) {
        guard !isCapturing else { return }
        guard ensurePermission() else { return }
        prepareForCapture()
        isCapturing = true

        Task {
            defer { isCapturing = false }
            do {
                switch kind {
                case .fullScreen:
                    status = "Capturing…"
                    let screens: [NSScreen]
                    if preferences.monitor == 1 {
                        screens = NSScreen.screens
                    } else if let screen = captureService.screenUnderPointer() {
                        screens = [screen]
                    } else {
                        screens = NSScreen.screens
                    }
                    let shots = try await captureService.capture(screens: screens)
                    guard let image = ImageComposer.fullImage(from: shots) else {
                        throw CaptureService.CaptureError.noDisplays
                    }
                    CaptureFeedback.play(
                        flash: preferences.flash,
                        sound: preferences.shutter,
                        screens: screens
                    )
                    screenPermission = true
                    await finish(image: image)

                case .area:
                    status = "Drag to select an area."
                    let shots = try await captureService.capture(screens: NSScreen.screens)
                    screenPermission = true
                    let rect = await areaSelector.select(shots: shots)
                    guard let rect else {
                        status = "Capture cancelled."
                        return
                    }
                    guard let image = ImageComposer.compose(shots: shots, rect: rect) else {
                        throw CaptureService.CaptureError.failed("The selected area could not be read.")
                    }
                    let involved = NSScreen.screens.filter { $0.frame.intersects(rect) }
                    CaptureFeedback.play(
                        flash: preferences.flash,
                        sound: preferences.shutter,
                        screens: involved.isEmpty ? NSScreen.screens : involved
                    )
                    await finish(image: image)
                }
            } catch {
                handleCaptureFailure(error)
            }
        }
    }

    /// Closing the window or starting a capture keeps Grab Pic in the background. The window is
    /// removed before the frozen frame is taken so the utility never appears in its own capture.
    private func prepareForCapture() {
        if let window = windowController?.window, window.isVisible {
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Without access, explain once and offer the guided path instead of letting several system
    /// prompts appear. Builds are signed with a stable requirement, so a fresh process's answer
    /// is reliable.
    private func ensurePermission() -> Bool {
        if captureService.hasScreenPermission {
            screenPermission = true
            return true
        }
        screenPermission = false
        status = "Screen Recording is off for Grab Pic."
        presentPermissionAlert()
        return false
    }

    private var permissionAlertVisible = false

    /// True in the process that was relaunched to ask macOS for access. Until the user switches
    /// Grab Pic on (and macOS restarts it), Settings shows the single next step.
    @Published private(set) var permissionRequestInFlight = false

    private func presentPermissionAlert() {
        guard !permissionAlertVisible else { return }
        permissionAlertVisible = true
        defer { permissionAlertVisible = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow Grab Pic to record your screen"
        alert.informativeText = permissionRequestInFlight
            ? "Switch on Grab Pic in System Settings → Screen & System Audio Recording. macOS will offer Quit & Reopen; choose it and you're done."
            : "One permission covers screenshots, screen recordings, and their sound. Grab Pic opens System Settings for you: switch Grab Pic on, then choose Quit & Reopen."
        alert.addButton(withTitle: permissionRequestInFlight ? "Open System Settings" : "Continue")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            allowScreenRecording()
        }
    }

    /// The one path to Screen Recording access.
    ///
    /// macOS only adds an app to the Screen Recording list when that app asks, and it answers a
    /// repeated ask in the same process silently. An approval granted to an older build also stays
    /// in the list as "on" while refusing this build. So Grab Pic clears its own stale entry,
    /// restarts itself, and the fresh process asks once and opens the right pane. The user flips
    /// one switch; macOS's own Quit & Reopen finishes the job.
    func allowScreenRecording() {
        if permissionRequestInFlight {
            openScreenPrivacySettings()
            return
        }
        if captureService.hasScreenPermission {
            screenPermission = true
            return
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.owl.grabpic"
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", bundleID]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        try? reset.run()
        reset.waitUntilExit()
        relaunch(arguments: ["--request-permission"])
    }

    /// Runs in the relaunched process: registers Grab Pic in the Screen Recording list and opens
    /// that pane with Settings showing the next step.
    func requestPermissionAfterRelaunch() {
        permissionRequestInFlight = true
        showSettings()
        if captureService.hasScreenPermission {
            permissionRequestInFlight = false
            screenPermission = true
            return
        }
        _ = CGRequestScreenCaptureAccess()
        status = "Switch on Grab Pic in System Settings, then choose Quit & Reopen."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.openScreenPrivacySettings()
        }
    }

    /// macOS applies a new Screen Recording approval only to a fresh process.
    func relaunch(arguments: [String] = ["--show"]) {
        let path = Bundle.main.bundleURL.path
        // -n: a new instance even though this one is still quitting; the old one exits right away.
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"$0\" --args \"$@\"", path] + arguments
        do {
            try script.run()
            NSApp.terminate(nil)
        } catch {
            status = "Could not reopen Grab Pic. Quit and open it again."
        }
    }

    func openScreenPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        if let captureError = error as? CaptureService.CaptureError,
           case .permission = captureError {
            screenPermission = false
            status = "Screen Recording is off for Grab Pic."
            presentPermissionAlert()
            return
        }
        status = "Capture failed: \(error.localizedDescription)"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Saving

    private func finish(image: CGImage, copyToClipboard: Bool = true) async {
        let settings = preferences.captureSettings
        let copy = copyToClipboard && preferences.copy
        do {
            // Encode once, off the main thread. A PNG capture reuses the same bytes for the
            // clipboard, so a large Retina grab is never encoded twice.
            let saved = try await Task.detached(priority: .userInitiated) { () -> (URL, Data?, Int) in
                let result = try CaptureStore.saveReturningData(image, settings: settings)
                var clip: Data? = nil
                if copy {
                    clip = settings.format == 0 ? result.data : CaptureStore.pngData(for: image)
                }
                return (result.url, clip, result.data.count)
            }.value
            let url = saved.0
            RecentCapture.remember(url)

            var note = "Saved"
            if copy {
                if let png = saved.1, ClipboardService.copy(png: png, image: image) {
                    watcher.markOwnWrite()
                    note = "Saved and copied"
                } else {
                    note = "Saved; clipboard busy"
                }
            }

            let thumbnail = await Task.detached(priority: .utility) {
                ImageLoader.thumbnail(from: image)
            }.value
            let bytes = saved.2
            let detail = "\(image.width) × \(image.height) · \(bytes / 1024) KB · Just now"
            latest = LatestCapture(
                url: url,
                name: url.lastPathComponent,
                detail: detail,
                image: thumbnail,
                pixelWidth: image.width,
                pixelHeight: image.height
            )

            status = "\(note) · \(url.lastPathComponent)"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not save the capture"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func saveClipboardImage(_ image: CGImage) {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            status = "Saving image from the clipboard…"
            await finish(image: image, copyToClipboard: false)
            if !status.hasPrefix("Save failed") {
                status = "Clipboard image saved · \(latest?.path ?? "")"
            }
        }
    }

    // MARK: - Screen recording

    /// Shows the floating Stop control for the running recording, if it is not already up.
    func showFloatingStopControl() {
        guard isRecording, recordingHUD == nil else { return }
        let screen = captureService.screenUnderPointer() ?? NSScreen.main
        if let screen {
            recordingHUD = RecordingHUD(screen: screen, state: self)
        }
    }

    /// The record shortcut and the Record card: stop a running recording, otherwise show the bar
    /// (full screen or area, sound, microphone). Pressing it again while the bar is up records
    /// with the current choices.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else if recordingBar.isVisible {
            recordingBar.close()
            startRecording(preferences.recordMode == 1 ? .area : .fullScreen)
        } else {
            showRecordingBar()
        }
    }

    func showRecordingBar() {
        guard !isRecording, !isStoppingRecording, !isCapturing else { return }
        guard ensurePermission() else { return }
        prepareForCapture()
        recordingBar.show(state: self)
    }

    func startRecording(_ kind: CaptureKind) {
        guard !isRecording, !isStoppingRecording, !isCapturing else { return }
        recordingBar.close()
        guard ensurePermission() else { return }
        prepareForCapture()
        isCapturing = true

        Task {
            defer { isCapturing = false }
            do {
                guard var screen = captureService.screenUnderPointer() ?? NSScreen.main else {
                    throw CaptureService.CaptureError.noDisplays
                }
                var area: CGRect?
                if kind == .area {
                    status = "Drag to choose what to record."
                    let shots = try await captureService.capture(screens: NSScreen.screens)
                    screenPermission = true
                    guard let selection = await areaSelector.select(
                        shots: shots,
                        hint: "Drag to choose what to record   ·   Esc to cancel"
                    ) else {
                        status = "Recording cancelled."
                        return
                    }
                    // A recording follows one display: use the one holding most of the selection.
                    screen = NSScreen.screens.max(by: {
                        Self.area($0.frame.intersection(selection)) < Self.area($1.frame.intersection(selection))
                    }) ?? screen
                    area = selection.intersection(screen.frame)
                }
                guard let displayID = captureService.displayID(for: screen) else {
                    throw CaptureService.CaptureError.noDisplays
                }

                var microphone = preferences.recordMicrophone
                var micNote: String?
                if microphone, !(await Self.microphoneAllowed()) {
                    microphone = false
                    micNote = "Microphone is off: allow Grab Pic in System Settings → Privacy & Security → Microphone."
                }

                let finalURL = try CaptureStore.recordingURL(settings: preferences.captureSettings)
                let workingURL = finalURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(finalURL.deletingPathExtension().lastPathComponent).part.mp4")

                let recorder = ScreenRecorder()
                recorder.onUnexpectedStop = { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopRecording() }
                }
                try await recorder.start(ScreenRecorder.Options(
                    displayID: displayID,
                    screenFrame: screen.frame,
                    area: area,
                    backingScale: screen.backingScaleFactor,
                    framesPerSecond: preferences.recordFrameRate == 1 ? 60 : 30,
                    limitTo1080p: preferences.recordSize == 1,
                    systemAudio: preferences.recordSystemAudio,
                    microphone: microphone,
                    showsCursor: preferences.recordCursor,
                    outputURL: workingURL
                ))
                screenPermission = true
                screenRecorder = recorder
                recordingFinalURL = finalURL
                recordingStartedAt = Date()
                activeRecordingMode = kind == .area ? 1 : 0
                recordingMicrophone = preferences.recordMicrophone ? (microphone && recorder.microphoneActive) : nil
                recordingSystemAudio = preferences.recordSystemAudio
                isRecording = true
                if let area {
                    recordingBorder = RecordingBorder(rect: area, screen: screen)
                }
                if preferences.recordFloatingControl {
                    recordingHUD = RecordingHUD(screen: screen, state: self)
                }
                if microphone && !recorder.microphoneActive {
                    micNote = "Recording without the microphone: it could not be opened."
                }
                status = micNote ?? "Recording… press \(shortcutLabel(for: .record)) or use the menu bar to stop."
            } catch {
                handleCaptureFailure(error)
            }
        }
    }

    func stopRecording(then completion: (() -> Void)? = nil) {
        guard let recorder = screenRecorder, !isStoppingRecording else {
            completion?()
            return
        }
        isStoppingRecording = true
        status = "Saving recording…"
        recordingBorder?.close()
        recordingBorder = nil
        let finalURL = recordingFinalURL

        Task {
            defer {
                screenRecorder = nil
                recordingFinalURL = nil
                recordingStartedAt = nil
                activeRecordingMode = nil
                recordingMicrophone = nil
                recordingHUD?.close()
                recordingHUD = nil
                isRecording = false
                isStoppingRecording = false
                completion?()
            }
            do {
                let working = try await recorder.stop()
                var saved = working
                if let finalURL {
                    try FileManager.default.moveItem(at: working, to: finalURL)
                    saved = finalURL
                }
                RecentCapture.remember(saved)
                if preferences.copy {
                    copyFileReference(saved)
                }
                if let video = await VideoInfo.load(saved) {
                    latest = video
                }
                status = preferences.copy
                    ? "Recording saved and copied · \(saved.lastPathComponent)"
                    : "Recording saved · \(saved.lastPathComponent)"
            } catch {
                status = "Recording failed: \(error.localizedDescription)"
                if completion == nil {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "The recording could not be saved"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    var recordingElapsed: String {
        guard let start = recordingStartedAt else { return "0:00" }
        return Self.duration(Date().timeIntervalSince(start))
    }

    nonisolated static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Puts the recording on the clipboard the way Finder's Copy does, so it pastes as a video
    /// attachment into Finder, Mail, Messages, Slack, WhatsApp, and browsers.
    private func copyFileReference(_ url: URL) {
        if ClipboardService.copyFile(url) {
            watcher.markOwnWrite()
        }
    }

    // MARK: - Latest capture

    func loadLatest(force: Bool) async {
        latestRequest += 1
        let request = latestRequest
        if !force, let latest, FileManager.default.fileExists(atPath: latest.url.path) {
            return
        }
        let folder = preferences.folderURL
        let found: URL? = await Task.detached(priority: .utility) {
            RecentCapture.storedURL() ?? RecentCapture.newestCapture(in: folder)
        }.value
        guard request == latestRequest, let url = found else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if url.pathExtension.lowercased() == "mp4" {
            let video = await VideoInfo.load(url)
            guard request == latestRequest else { return }
            latest = video
            return
        }

        let loaded = await Task.detached(priority: .utility) { () -> (NSImage?, ImageLoader.Metadata?) in
            (ImageLoader.thumbnail(at: url), ImageLoader.metadata(at: url))
        }.value
        guard request == latestRequest else { return }

        let metadata = loaded.1
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let bytes = metadata?.bytes ?? 0
        let width = metadata?.pixelWidth ?? Int(loaded.0?.size.width ?? 0)
        let height = metadata?.pixelHeight ?? Int(loaded.0?.size.height ?? 0)
        latest = LatestCapture(
            url: url,
            name: url.lastPathComponent,
            detail: "\(width) × \(height) · \(bytes / 1024) KB · \(modified.formatted(date: .numeric, time: .shortened))",
            image: loaded.0,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    func openPreview() {
        guard let latest else { return }
        if latest.isVideo {
            NSWorkspace.shared.open(latest.url)
            return
        }
        let url = latest.url
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let cg = ImageLoader.cgImage(at: url) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            preview = LatestCapture(
                url: latest.url,
                name: latest.name,
                detail: latest.detail,
                image: loaded ?? latest.image,
                pixelWidth: latest.pixelWidth,
                pixelHeight: latest.pixelHeight
            )
        }
    }

    func closePreview() {
        preview = nil
    }

    func copyLatest() {
        guard let latest else { return }
        let url = latest.url
        if latest.isVideo {
            copyFileReference(url)
            status = "Recording copied. Paste it into Finder, Mail, or a chat."
            return
        }
        Task {
            let image = await Task.detached(priority: .userInitiated) { ImageLoader.cgImage(at: url) }.value
            guard let image else {
                status = "The latest capture could not be read."
                return
            }
            if ClipboardService.copy(image) {
                watcher.markOwnWrite()
                status = "Latest capture copied."
            } else {
                status = "The clipboard is busy. Try again."
            }
        }
    }

    func revealLatest() {
        guard let latest else { return }
        guard FileManager.default.fileExists(atPath: latest.url.path) else {
            status = "The latest capture is no longer on disk."
            self.latest = nil
            Task { await loadLatest(force: true) }
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([latest.url])
    }

    func openFolder() {
        let root = preferences.folderURL
        // Land on the folder captures made now would use — today, this ISO week, or this month —
        // so the newest grabs are visible instead of a list of past periods. Before the first
        // capture of a period, fall back to the root so the Finder window is never empty.
        let period = preferences.periodFolderURL()
        let hasPeriod = FileManager.default.fileExists(atPath: period.path)
        let target = hasPeriod ? period : root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            NSWorkspace.shared.open(target)
            status = "Opened \(target.path)"
        } catch {
            status = "Could not open the capture folder: \(error.localizedDescription)"
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferences.folderURL
        panel.prompt = "Choose"
        panel.message = "Choose a home for everything you grab."
        if panel.runModal() == .OK, let url = panel.url {
            preferences.folder = url.path
            status = "Capture folder changed."
            Task { await loadLatest(force: true) }
        }
    }

    // MARK: - Shortcuts

    func validate(binding: ShortcutBinding, for action: CaptureAction) -> String? {
        if let error = binding.validationError() { return error }
        for other in CaptureAction.allCases where other != action {
            if preferences.shortcut(for: other) == binding {
                return "That shortcut is already assigned to another Grab Pic action."
            }
        }
        return nil
    }

    @discardableResult
    func setShortcut(_ binding: ShortcutBinding?, for action: CaptureAction) -> String? {
        let previous = preferences.shortcut(for: action)
        if let binding, let error = validate(binding: binding, for: action) {
            return error
        }
        if let error = shortcuts.register(action, binding: binding) {
            _ = shortcuts.register(action, binding: previous)
            return error
        }
        preferences.setShortcut(binding, for: action)
        if let binding {
            status = "\(action.title) shortcut saved · \(binding.label)"
        } else {
            status = "\(action.title) shortcut cleared."
        }
        return nil
    }

    func resetShortcuts() {
        var errors: [String] = []
        for action in CaptureAction.allCases {
            if let error = setShortcut(action.defaultBinding, for: action) {
                errors.append("\(action.title): \(error)")
            }
        }
        status = errors.first ?? "Default shortcuts restored."
    }

    func shortcutLabel(for action: CaptureAction) -> String {
        preferences.shortcut(for: action)?.label ?? "No shortcut assigned"
    }

    private func registerConfiguredShortcuts() {
        var errors: [String] = []
        for action in CaptureAction.allCases {
            if let error = shortcuts.register(action, binding: preferences.shortcut(for: action)) {
                errors.append("\(action.title): \(error)")
            }
        }
        if let first = errors.first {
            status = first
        }
    }

    // MARK: - Login item

    /// Printed by the `--status` launch word: the few system facts that decide whether the app can
    /// capture and start at login, without opening a window.
    var diagnostics: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        return """
        Grab Pic \(version)
        bundle: \(Bundle.main.bundlePath)
        screen recording: \(captureService.hasScreenPermission ? "allowed" : "not allowed")
        start at login: \(LoginItemService.description)
        capture folder: \(preferences.folderURL.path)
        menu bar icon: \(preferences.menuBarIcon ? "shown" : "hidden")
        """
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            try LoginItemService.set(enabled)
            refreshSystemState()
            if !loginItemEnabled && enabled {
                status = LoginItemService.explanation ?? "macOS did not enable the login item."
            } else {
                status = enabled ? "Grab Pic will start in the menu bar when you sign in." : "Start at login turned off."
            }
        } catch {
            refreshSystemState()
            loginItemNote = "Could not update login item: \(error.localizedDescription)"
            status = "Could not update login item: \(error.localizedDescription)"
        }
    }

    // MARK: - Browser server hand-off (not included in this build)

    var isPreviewBuild: Bool { !servicesEnabled }
}
