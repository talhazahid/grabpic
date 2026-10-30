import Carbon.HIToolbox
import AppKit
import ServiceManagement

/// Registers system-wide keyboard combinations through Carbon's public hot-key API, which works
/// without Accessibility or Input Monitoring permissions. macOS-owned and conflicting
/// combinations are reported instead of being silently swallowed.
final class ShortcutService {
    static let shared = ShortcutService()

    var onInvoke: ((CaptureAction) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: CaptureAction] = [:]
    private var handlerRef: EventHandlerRef?
    private var installed = false
    private var pointer: UnsafeMutableRawPointer?
    private let signature: OSType = 0x47524142 // 'GRAB'

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(_ action: CaptureAction, binding: ShortcutBinding?) -> String? {
        installIfNeeded()
        unregister(action)
        guard let binding else { return nil }
        if let error = binding.validationError() { return error }

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: UInt32(action.rawValue))
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            if status == -9878 {
                return "macOS or another app is already using that shortcut."
            }
            return "That shortcut could not be registered by macOS (error \(status))."
        }
        refs[UInt32(action.rawValue)] = reference
        actions[UInt32(action.rawValue)] = action
        return nil
    }

    func unregister(_ action: CaptureAction) {
        let key = UInt32(action.rawValue)
        if let reference = refs[key] {
            UnregisterEventHotKey(reference)
        }
        refs[key] = nil
        actions[key] = nil
    }

    func unregisterAll() {
        for reference in refs.values {
            UnregisterEventHotKey(reference)
        }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func handle(id: UInt32) {
        guard let action = actions[id] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onInvoke?(action)
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        pointer = Unmanaged.passUnretained(self).toOpaque()
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            grabpicHotKeyHandler,
            1,
            &specification,
            pointer,
            &handlerRef
        )
        installed = status == noErr
    }
}

private func grabpicHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let service = Unmanaged<ShortcutService>.fromOpaque(userData).takeUnretainedValue()
    service.handle(id: identifier.id)
    return noErr
}

enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            // Re-register even when the item is already enabled: SMAppService has no API for reading
            // the registered bundle path, so this is the only way to repoint a login item after the
            // app has been moved. Unregistering first also avoids an "already registered" error.
            try? SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Only approval needs the owner's attention. `.notFound` and `.notRegistered` are both the
    /// normal "not enabled yet" states, so they stay quiet instead of suggesting a fix.
    static var explanation: String? {
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Allow Grab Pic in System Settings → General → Login Items."
        default:
            return nil
        }
    }

    /// Plain-language state for the `--status` diagnostic.
    static var description: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "waiting for approval in System Settings → General → Login Items"
        case .notRegistered: return "not registered"
        case .notFound: return "not found"
        @unknown default: return "unknown (\(SMAppService.mainApp.status.rawValue))"
        }
    }
}
