import Carbon.HIToolbox
import Foundation

/// Registers a system-wide hot key through Carbon's RegisterEventHotKey.
/// This path needs no Accessibility permission, unlike CGEventTap / global NSEvent key monitors.
final class HotKeyManager {
    private let definition: HotKeyDefinition
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private static let signature: OSType = 0x434C_4950 // 'CLIP'

    init(definition: HotKeyDefinition, handler: @escaping () -> Void) {
        self.definition = definition
        self.handler = handler
    }

    /// Returns nil on success, otherwise the failing OSStatus.
    @discardableResult
    func register() -> OSStatus? {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.handler() }
            return noErr
        }, 1, &eventType, userData, &eventHandlerRef)
        guard installStatus == noErr else { return installStatus }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(definition.keyCode, definition.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr ? nil : status
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit { unregister() }
}
