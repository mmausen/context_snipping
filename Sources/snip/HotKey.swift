import AppKit
import Carbon.HIToolbox

/// Dünner Wrapper um die Carbon Hot-Key-API. Registriert systemweite
/// Tastenkombinationen, ohne dass die App im Vordergrund sein muss – und
/// ohne zusätzliche Berechtigung (im Gegensatz zu einem CGEvent-Tap).
final class HotKey {
    private var ref: EventHotKeyRef?
    private let identifier: UInt32
    private let action: () -> Void

    private static var registry: [UInt32: HotKey] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static var handlerInstalled = false

    @discardableResult
    init?(keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.identifier = HotKey.nextIdentifier
        HotKey.nextIdentifier += 1
        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x534E_4950), id: identifier) // 'SNIP'
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            NSLog("snip: Hotkey \(keyCode)/\(modifiers) konnte nicht registriert werden (Status \(status)) – vermutlich schon vergeben.")
            return nil
        }
        HotKey.registry[identifier] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.registry[identifier] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
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
                HotKey.registry[hotKeyID.id]?.action()
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}

/// Carbon-Modifier als bequeme Konstanten.
enum Mod {
    static let cmd = UInt32(cmdKey)
    static let opt = UInt32(optionKey)
    static let ctrl = UInt32(controlKey)
    static let shift = UInt32(shiftKey)
}

enum Key {
    static let s = kVK_ANSI_S
    static let c = kVK_ANSI_C
    static let ret = kVK_Return
    static let period = kVK_ANSI_Period
}
