import Carbon.HIToolbox
import ClamCore

/// One global hot key, registered with Carbon. Needs no permission.
final class HotkeyManager {
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: HotkeyBinding?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue().onPress?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Registers `binding`, replacing the current one. On failure the current one stays.
    func register(_ binding: HotkeyBinding) -> Bool {
        guard binding.isValid else { return false }
        if binding == current { return true }

        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x434C_414D, id: 1)   // 'CLAM'
        let status = RegisterEventHotKey(binding.keyCode, binding.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newRef
        current = binding
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        current = nil
    }
}
