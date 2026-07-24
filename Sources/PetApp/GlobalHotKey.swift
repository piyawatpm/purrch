import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses Carbon's hot key API rather than `NSEvent.addGlobalMonitorForEvents`
/// specifically because it needs no Accessibility permission — worth the dated
/// API for a personal app that shouldn't demand a scary prompt on first launch.
final class GlobalHotKey {
    /// Registered actions, keyed by hot key id, so the C callback (which can't
    /// capture context) can find its way back to the right closure.
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Returns nil if the combination is already taken by another app.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                guard status == noErr else { return status }
                GlobalHotKey.handlers[pressed.id]?()
                return noErr
            },
            1, &spec, nil, &handlerRef)
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50455431), id: id)   // 'PET1'
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
        GlobalHotKey.handlers[id] = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        GlobalHotKey.handlers[id] = nil
    }

    /// Control-Option-Space: deliberately away from Spotlight's ⌘Space and the
    /// Character Viewer's ⌃⌘Space.
    static func quickAdd(action: @escaping () -> Void) -> GlobalHotKey? {
        GlobalHotKey(keyCode: UInt32(kVK_Space),
                     modifiers: UInt32(controlKey | optionKey),
                     action: action)
    }

    static let quickAddDescription = "\u{2303}\u{2325}Space"
}
