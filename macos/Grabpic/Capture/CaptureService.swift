import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    enum CaptureError: LocalizedError {
        case permission
        case noDisplays
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .permission:
                return "Screen Recording access is required to capture your display."
            case .noDisplays:
                return "No capturable displays were found."
            case .failed(let message):
                return message
            }
        }
    }

    /// Set once ScreenCaptureKit has actually delivered content in this process. This is the
    /// ground truth: `CGPreflightScreenCaptureAccess()` caches its answer per process and can
    /// stay `false` after the user has switched Grab Pic on, so it is never used as a hard gate.
    private(set) var verifiedAccess = false
    private var requestedThisLaunch = false

    var hasScreenPermission: Bool {
        verifiedAccess || CGPreflightScreenCaptureAccess()
    }

    /// Asks ScreenCaptureKit directly. Returns true when the system really lets Grab Pic read the
    /// screen, regardless of what the cached preflight answer says.
    func probeAccess() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            verifiedAccess = true
            return true
        } catch {
            if Self.isPermissionError(error) { verifiedAccess = false }
            return verifiedAccess
        }
    }

    /// Shows the system prompt at most once per launch. macOS only shows it the first time.
    func requestScreenPermissionOnce() {
        guard !requestedThisLaunch else { return }
        requestedThisLaunch = true
        _ = CGRequestScreenCaptureAccess()
    }

    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return true
        }
        // TCC denials sometimes surface as a generic failure to get content.
        let text = nsError.localizedDescription.lowercased()
        return text.contains("declined") || text.contains("not authorized") || text.contains("permission")
    }

    func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Captures each requested screen at native pixel density. Displays are captured concurrently
    /// so multi-monitor grabs cost about as much as a single one.
    func capture(screens: [NSScreen]) async throws -> [DisplayShot] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            verifiedAccess = true
        } catch {
            if Self.isPermissionError(error) || !CGPreflightScreenCaptureAccess() {
                verifiedAccess = false
                throw CaptureError.permission
            }
            throw CaptureError.failed(error.localizedDescription)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        var displays: [CGDirectDisplayID: SCDisplay] = [:]
        for display in content.displays {
            displays[display.displayID] = display
        }

        struct Job {
            let id: CGDirectDisplayID
            let frame: CGRect
            let filter: SCContentFilter
            let configuration: SCStreamConfiguration
        }

        var jobs: [Job] = []
        for screen in screens {
            guard let id = displayID(for: screen), let display = displays[id] else { continue }
            let configuration = SCStreamConfiguration()
            // SCDisplay reports the current mode's size, which can be the point size on scaled
            // displays. Ask for the backing-store resolution so captures stay crisp.
            let scale = max(1, screen.backingScaleFactor)
            configuration.width = max(1, Int((screen.frame.width * scale).rounded()))
            configuration.height = max(1, Int((screen.frame.height * scale).rounded()))
            configuration.showsCursor = false
            configuration.backgroundColor = .clear
            configuration.scalesToFit = false
            if #available(macOS 14.0, *) {
                configuration.captureResolution = .best
            }
            jobs.append(Job(
                id: id,
                frame: screen.frame,
                filter: SCContentFilter(display: display, excludingWindows: ownWindows),
                configuration: configuration
            ))
        }

        if jobs.isEmpty { throw CaptureError.noDisplays }

        var shots: [DisplayShot] = []
        var lastError: Error?
        await withTaskGroup(of: (Int, Result<CGImage, Error>).self) { group in
            for (index, job) in jobs.enumerated() {
                let filter = job.filter
                let configuration = job.configuration
                group.addTask {
                    do {
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: filter,
                            configuration: configuration
                        )
                        return (index, .success(image))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results: [(Int, CGImage)] = []
            for await (index, result) in group {
                switch result {
                case .success(let image): results.append((index, image))
                case .failure(let error): lastError = error
                }
            }
            for (index, image) in results.sorted(by: { $0.0 < $1.0 }) {
                let job = jobs[index]
                shots.append(DisplayShot(
                    screenID: job.id,
                    frame: job.frame,
                    // Derive density from the delivered image so composition stays exact even if
                    // the system clamps the requested size.
                    scale: CGFloat(image.width) / max(1, job.frame.width),
                    image: image
                ))
            }
        }

        if shots.isEmpty {
            if let lastError, Self.isPermissionError(lastError) {
                verifiedAccess = false
                throw CaptureError.permission
            }
            if let lastError { throw CaptureError.failed(lastError.localizedDescription) }
            throw CaptureError.noDisplays
        }
        return shots
    }
}
