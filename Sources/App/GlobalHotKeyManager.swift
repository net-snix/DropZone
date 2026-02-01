import Carbon

final class GlobalHotKeyManager {
    struct Registration {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private var registrations: [Registration] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        registrations.append(Registration(id: id, keyCode: keyCode, modifiers: modifiers, handler: handler))
    }

    func start() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event else { return noErr }
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            manager.handlers[hotKeyID.id]?()
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
        guard status == noErr else { return }

        for registration in registrations {
            var hotKeyID = EventHotKeyID(signature: OSType(0x445A484B), id: registration.id)
            var hotKeyRef: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(
                registration.keyCode,
                registration.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if registerStatus == noErr {
                handlers[registration.id] = registration.handler
                hotKeyRefs.append(hotKeyRef)
            }
        }
    }

    func stop() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    static let defaultToggleKeyCode: UInt32 = UInt32(kVK_Shift)
    static let defaultToggleModifiers: UInt32 = 0
}
