import AppKit
import Combine
import Darwin

@main
enum GrabpicMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var menuBarCancellable: AnyCancellable?
    private var recordingCancellable: AnyCancellable?
    private var recordingTimer: Timer?
    private var recordingTick = 0
    private var repinnedThisRecording = false
    private var latePinDone = false
    private var launchedAtLogin = false
    private var finishedLaunching = false

    // MARK: - Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenApplication(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Grab Pic starts itself through its login item. macOS's own "reopen windows when logging
        // back in" would relaunch it a second way and restore the window, so opt out of both.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        NSApp.disableRelaunchOnLogin()
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        finishedLaunching = true
        buildStatusItem()
        observeMenuBarPreference()
        observeRecording()
        state.launch(showWindow: shouldShowInitialWindow())
        performLaunchCommand()
    }

    /// Windows accepts `full`, `area`, `folder`, `settings`, `quit`, and `background` arguments;
    /// the Mac build understands the same words so scripts and login items behave alike.
    private enum LaunchCommand: String {
        case full, area, folder, settings, quit, background, show, startup, status
        case noStartup = "no-startup"
        case requestPermission = "request-permission"
        case recordTest = "record-test"
    }

    private var launchCommand: LaunchCommand? {
        for argument in ProcessInfo.processInfo.arguments.dropFirst() {
            let trimmed = argument.hasPrefix("--") ? String(argument.dropFirst(2)) : argument
            if let command = LaunchCommand(rawValue: trimmed.lowercased()) { return command }
        }
        return nil
    }

    private func performLaunchCommand() {
        switch launchCommand {
        case .settings: state.showSettings()
        case .folder: state.openFolder()
        case .full: state.capture(.fullScreen)
        case .area: state.capture(.area)
        case .quit: state.quit()
        case .startup: state.setLoginItem(true)
        case .noStartup: state.setLoginItem(false)
        case .status: print(state.diagnostics); exit(0)
        case .requestPermission: state.requestPermissionAfterRelaunch()
        case .recordTest:
            // QA: record six seconds of the current display, logging the menu bar item each second.
            debugLogging = true
            debugLog("record-test: start")
            state.startRecording(.fullScreen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
                MainActor.assumeIsolated {
                    self?.debugLog("record-test: stop")
                    self?.state.stopRecording()
                }
            }
        case .background, .show, .none: break
        }
    }

    private func shouldShowInitialWindow() -> Bool {
        switch launchCommand {
        case .background, .full, .area, .folder, .settings, .quit, .startup, .noStartup, .status,
             .requestPermission, .recordTest: return false
        case .show: return true
        case .none: return !launchedFromLoginItem
        }
    }

    /// The open-application event carries a login-item flag when the system starts the app at
    /// login. Both the installed handler and the current event are consulted because the event can
    /// arrive before the delegate finishes launching.
    private var launchedFromLoginItem: Bool {
        if launchedAtLogin { return true }
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(0x6C676974))?.booleanValue == true {
            return true
        }
        // macOS does not always attach the login flag. A launch within moments of the Dock
        // starting (that is, of the user signing in) is treated as a login launch, so Grab Pic
        // stays in the menu bar instead of opening a window over the desktop.
        return Self.launchedSoonAfterSignIn
    }

    private static var launchedSoonAfterSignIn: Bool {
        let now = Date()
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
           let started = dock.launchDate ?? processStartDate(pid: dock.processIdentifier) {
            return now.timeIntervalSince(started) < 90
        }
        return ProcessInfo.processInfo.systemUptime < 180
    }

    private static func processStartDate(pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// LaunchServices includes this parameter when the app is started by a login item.
    /// If the flag is absent the app behaves like a normal utility launch and opens.
    @objc private func handleOpenApplication(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        let loginKeyword = AEKeyword(0x6C676974) // 'lgit'
        if let descriptor = event.paramDescriptor(forKeyword: loginKeyword),
           descriptor.descriptorType == typeBoolean,
           descriptor.booleanValue {
            launchedAtLogin = true
        }
        if finishedLaunching {
            state.showApp()
        }
    }

    // MARK: - Reopen and terminate

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        state.showApp()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting mid-recording finishes the file first, so nothing recorded is lost.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.isRecording else { return .terminateNow }
        state.stopRecording {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShortcutService.shared.unregisterAll()
    }

    // MARK: - Menu bar

    private static let statusItemName = "GrabpicStatusItem"

    private static let positionKey = "NSStatusItem Preferred Position \(statusItemName)"
    private static let savedPositionKey = "GrabpicStatusItemPositionBeforeRecording"

    /// Normally the icon sits where macOS puts new menu bar icons: at the left of the extras,
    /// beside other apps, where it is easy to spot (or wherever the user ⌘-drags it).
    ///
    /// While recording, macOS places its purple screen-sharing button exactly where that is and
    /// draws over it, so the red recording icon moves to the right end, beside Control Center, and
    /// returns to its usual place when the recording stops.
    private func buildStatusItem(duringRecording: Bool = false) {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "GrabpicStatusItemLeftDefault") {
            // Earlier builds always pinned the icon to the far right; return it to the usual place once.
            defaults.removeObject(forKey: Self.positionKey)
            defaults.set(true, forKey: "GrabpicStatusItemLeftDefault")
        }
        if duringRecording {
            if let current = defaults.object(forKey: Self.positionKey) {
                defaults.set(current, forKey: Self.savedPositionKey)
            } else {
                defaults.removeObject(forKey: Self.savedPositionKey)
            }
            defaults.set(0.0, forKey: Self.positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.statusItemName
        item.isVisible = state.preferences.menuBarIcon
        if let button = item.button {
            let image = StatusIcon.make()
            button.image = image
            button.imageScaling = .scaleNone
            button.imagePosition = .imageOnly
            button.toolTip = "Grab Pic"
            button.setAccessibilityLabel("Grab Pic")
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// The menu bar icon can be hidden from Settings. The item is kept alive and only its
    /// visibility changes, so turning it back on needs no rebuild of the menu.
    private func observeMenuBarPreference() {
        menuBarCancellable = state.preferences.$menuBarIcon
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // While recording the stop control must stay reachable.
                    self.statusItem?.isVisible = isVisible || self.state.isRecording
                }
            }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()
        for item in buildStatusMenu().items {
            item.menu?.removeItem(item)
            menu.addItem(item)
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if state.isRecording {
            let stop = NSMenuItem(
                title: "Stop Recording  (\(state.recordingElapsed))",
                action: #selector(menuToggleRecording),
                keyEquivalent: ""
            )
            stop.target = self
            stop.isEnabled = !state.isStoppingRecording
            menu.addItem(stop)
            menu.addItem(.separator())
        }

        let full = NSMenuItem(title: "Grab Full Screen", action: #selector(menuFullScreen), keyEquivalent: "")
        full.target = self
        menu.addItem(full)

        let area = NSMenuItem(title: "Grab Area", action: #selector(menuArea), keyEquivalent: "")
        area.target = self
        menu.addItem(area)

        menu.addItem(.separator())

        if !state.isRecording {
            let record = NSMenuItem(title: "Record Full Screen", action: #selector(menuRecordFull), keyEquivalent: "")
            record.target = self
            menu.addItem(record)
            let recordArea = NSMenuItem(title: "Record Area", action: #selector(menuRecordArea), keyEquivalent: "")
            recordArea.target = self
            menu.addItem(recordArea)
            menu.addItem(.separator())
        }

        let captures = NSMenuItem(title: "Open Captures", action: #selector(menuOpenCaptures), keyEquivalent: "")
        captures.target = self
        menu.addItem(captures)

        let open = NSMenuItem(title: "Open Grab Pic…", action: #selector(menuOpenApp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Grab Pic", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func menuFullScreen() { state.capture(.fullScreen) }
    @objc private func menuArea() { state.capture(.area) }
    @objc private func menuOpenCaptures() { state.openFolder() }
    @objc private func menuToggleRecording() { state.toggleRecording() }
    @objc private func menuRecordArea() { state.startRecording(.area) }
    @objc private func menuRecordFull() { state.startRecording(.fullScreen) }
    @objc private func menuOpenApp() { state.showApp() }
    @objc private func menuSettings() { state.showSettings() }
    @objc private func menuQuit() { state.quit() }
    @objc private func menuAbout() { showAbout() }

    // MARK: - Recording indicator

    private func observeRecording() {
        recordingCancellable = state.$isRecording
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                MainActor.assumeIsolated { self?.updateRecordingIndicator(recording) }
            }
    }

    private func updateRecordingIndicator(_ recording: Bool) {
        defer { debugLog("indicator recording=\(recording)") }
        if recording, !repinnedThisRecording, let old = statusItem {
            repinnedThisRecording = true
            // Re-create the item at the right end so the stop control and timer are visible.
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
            buildStatusItem(duringRecording: true)
        }
        if !recording, repinnedThisRecording, let old = statusItem {
            // Back to where the icon was before the recording.
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
            let defaults = UserDefaults.standard
            if let saved = defaults.object(forKey: Self.savedPositionKey) {
                defaults.set(saved, forKey: Self.positionKey)
            } else {
                defaults.removeObject(forKey: Self.positionKey)
            }
            buildStatusItem()
        }
        guard let item = statusItem, let button = item.button else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if recording {
            // While recording the icon itself is the stop button: no menu, one click stops.
            item.isVisible = true
            item.menu = nil
            // Red pulsing icon plus the running time; one click stops.
            item.length = NSStatusItem.variableLength
            button.target = self
            button.action = #selector(statusItemClickedWhileRecording)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.image = StatusIcon.recording(level: 1)
            button.title = " " + state.recordingElapsed
            button.toolTip = "Recording. Click to stop."
            button.setAccessibilityLabel("Stop recording")

            recordingTick = 0
            let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let button = self.statusItem?.button else { return }
                    self.recordingTick += 1
                    let tick = self.recordingTick
                    // A slow breathing pulse, about 1.6 s per cycle.
                    let phase = Double(tick) / 15.0 * (2 * Double.pi / 1.6)
                    let level = 0.55 + 0.45 * (0.5 + 0.5 * cos(phase))
                    button.image = StatusIcon.recording(level: CGFloat(level))
                    if tick % 15 == 0 {
                        self.debugLog("tick \(tick / 15)s")
                        let elapsed = self.state.recordingElapsed
                        button.title = self.state.isStoppingRecording ? " Saving…" : " " + elapsed
                        button.toolTip = "Recording \(elapsed). Click to stop."
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            recordingTimer = timer

            // macOS adds its own sharing indicator about a second in. If that pushed the icon out of
            // view, pin it right once more; if it is still hidden, show the floating Stop control so
            // the recording can always be stopped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.state.isRecording, !self.isStatusItemOnScreen(),
                          !self.latePinDone else { return }
                    self.latePinDone = true
                    self.debugLog("hidden after sharing indicator; re-pinning")
                    if let old = self.statusItem {
                        NSStatusBar.system.removeStatusItem(old)
                        self.statusItem = nil
                        self.recordingTimer?.invalidate()
                        self.recordingTimer = nil
                        UserDefaults.standard.set(0.0, forKey: Self.positionKey)
                        self.buildStatusItem()
                        self.updateRecordingIndicator(true)
                    }
                }
            }

        } else {
            repinnedThisRecording = false
            latePinDone = false
            button.target = nil
            button.action = nil
            item.length = NSStatusItem.squareLength
            button.title = ""
            button.image = StatusIcon.make()
            button.imagePosition = .imageOnly
            button.toolTip = "Grab Pic"
            button.setAccessibilityLabel("Grab Pic")
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            item.menu = menu
            item.isVisible = state.preferences.menuBarIcon
        }
    }

    /// Appends the menu bar item's real state to recording-debug.log in the profile folder.
    private var debugLogging = false

    private func debugLog(_ event: String) {
        guard debugLogging else { return }
        var line = "\(Date().formatted(.iso8601)) \(event)"
        if let item = statusItem {
            let button = item.button
            let window = button?.window
            line += " | visible=\(item.isVisible) length=\(item.length) recording=\(state.isRecording)"
            line += " title='\(button?.title ?? "nil")' hasImage=\(button?.image != nil) menu=\(item.menu != nil)"
            if let window {
                line += " frame=\(NSStringFromRect(window.frame)) occlusionVisible=\(window.occlusionState.contains(.visible)) onScreen=\(window.isVisible)"
                if let screen = window.screen {
                    line += " screen=\(NSStringFromRect(screen.frame)) notchTop=\(screen.safeAreaInsets.top)"
                    if let r = screen.auxiliaryTopRightArea { line += " rightArea=\(NSStringFromRect(r))" }
                }
            } else {
                line += " window=nil"
            }
            line += " onScreenCheck=\(isStatusItemOnScreen())"
        } else {
            line += " | statusItem=nil"
        }
        let url = Preferences.profileDirectory.appendingPathComponent("recording-debug.log")
        try? FileManager.default.createDirectory(at: Preferences.profileDirectory, withIntermediateDirectories: true)
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// True when the status item is actually drawn where the user can see it.
    private func isStatusItemOnScreen() -> Bool {
        guard let item = statusItem, item.isVisible,
              let window = item.button?.window,
              window.occlusionState.contains(.visible) else { return false }
        let frame = window.frame
        guard frame.width > 0, let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else {
            return false
        }
        // On notched displays only the areas beside the notch are visible.
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea ?? .zero
            let right = screen.auxiliaryTopRightArea ?? .zero
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return NSMouseInRect(center, right, false) || NSMouseInRect(center, left, false)
        }
        return screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    @objc private func statusItemClickedWhileRecording() {
        state.stopRecording()
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Grab Pic")

        let about = NSMenuItem(title: "About Grab Pic", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: "Hide Grab Pic", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Grab Pic", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu

        let captureMenuItem = NSMenuItem()
        mainMenu.addItem(captureMenuItem)
        let captureMenu = NSMenu(title: "Capture")
        let grabFull = NSMenuItem(title: "Grab Full Screen", action: #selector(menuFullScreen), keyEquivalent: "")
        grabFull.target = self
        captureMenu.addItem(grabFull)
        let grabArea = NSMenuItem(title: "Grab Area", action: #selector(menuArea), keyEquivalent: "")
        grabArea.target = self
        captureMenu.addItem(grabArea)
        captureMenu.addItem(.separator())
        let recordScreen = NSMenuItem(title: "Record Full Screen", action: #selector(menuRecordFull), keyEquivalent: "")
        recordScreen.target = self
        captureMenu.addItem(recordScreen)
        let recordArea = NSMenuItem(title: "Record Area", action: #selector(menuRecordArea), keyEquivalent: "")
        recordArea.target = self
        captureMenu.addItem(recordArea)
        captureMenu.addItem(.separator())
        let openCaptures = NSMenuItem(title: "Open Captures", action: #selector(menuOpenCaptures), keyEquivalent: "")
        openCaptures.target = self
        captureMenu.addItem(openCaptures)
        captureMenuItem.submenu = captureMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func showAbout() {
        let credits = NSAttributedString(
            string: "Capture. Copy. Carry on.\nA native macOS port. Local by design.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.gpMuted
            ]
        )
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.6.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Grab Pic",
            .applicationVersion: version,
            .version: "",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
