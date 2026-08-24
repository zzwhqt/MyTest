import Carbon
import Foundation

final class HotKeyManager {
    private var visibilityHotKeyRef: EventHotKeyRef?
    private var stateLockHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onVisibilityPressed: (() -> Void)?
    var onStateLockPressed: (() -> Void)?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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
                DispatchQueue.main.async {
                    if identifier.id == 1 {
                        manager.onVisibilityPressed?()
                    } else if identifier.id == 2 {
                        manager.onStateLockPressed?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )

        let identifier = EventHotKeyID(signature: OSType(0x51555A31), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &visibilityHotKeyRef
        )

        let stateLockIdentifier = EventHotKeyID(signature: OSType(0x51555A31), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(cmdKey | optionKey),
            stateLockIdentifier,
            GetApplicationEventTarget(),
            0,
            &stateLockHotKeyRef
        )
    }

    deinit {
        if let visibilityHotKeyRef { UnregisterEventHotKey(visibilityHotKeyRef) }
        if let stateLockHotKeyRef { UnregisterEventHotKey(stateLockHotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
