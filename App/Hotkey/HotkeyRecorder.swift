import AppKit
import ClamCore
import SwiftUI

final class HotkeyRecorderModel: ObservableObject {
    /// The saved binding, active or not.
    @Published var binding: HotkeyBinding?
    /// False when the saved binding could not be registered (taken by another app, say).
    @Published var isActive: Bool
    @Published var isRecording = false
    @Published var message: String?

    /// Try to register a recorded binding. Returns whether it was accepted.
    var onRecord: ((HotkeyBinding) -> Bool)?
    var onClear: (() -> Void)?
    /// Release the registered hotkey so recording it does not fire it.
    var onSuspend: (() -> Void)?
    /// Register the saved binding again after a cancelled or refused recording.
    var onRestore: ((HotkeyBinding) -> Bool)?

    private var monitor: Any?
    private var suspended = false
    private var deactivationObserver: NSObjectProtocol?

    init(binding: HotkeyBinding?, isActive: Bool) {
        self.binding = binding
        self.isActive = binding != nil && isActive
        showAvailability()
        // Key presses stop reaching the recorder once another app is in front, and the
        // suspended hotkey may be the user's quick way to disarm: put it back.
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cancelRecording()
        }
    }

    deinit {
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
    }

    func toggleRecording() {
        isRecording ? cancelRecording() : start()
    }

    /// Ends a recording in progress, putting the previous hotkey back.
    func cancelRecording() {
        guard isRecording else { return }
        stop(restore: true)
        showAvailability()
    }

    /// Replaces the recording prompt with the saved binding's standing message, if it has one.
    private func showAvailability() {
        if let binding, !isActive {
            message = "\(binding.displayString) is unavailable. Record a new shortcut."
        } else {
            message = nil
        }
    }

    func clear() {
        stop(restore: false)
        binding = nil
        isActive = false
        message = nil
        onClear?()
    }

    private func start() {
        if isActive {
            onSuspend?()
            suspended = true
        }
        isRecording = true
        message = "Press a shortcut, or Esc to cancel."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil   // swallow the key press
        }
    }

    private func stop(restore: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        guard suspended else { return }
        suspended = false
        guard restore, let binding else { return }
        isActive = onRestore?(binding) == true
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {   // Escape
            cancelRecording()
            return
        }
        var modifiers: HotkeyBinding.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let code = UInt32(event.keyCode)
        let name = HotkeyKeyNames.name(forKeyCode: code)
            ?? event.charactersIgnoringModifiers?.uppercased()
            ?? "Key \(code)"
        let candidate = HotkeyBinding(keyCode: code, modifiers: modifiers, keyName: name)

        guard candidate.isValid else {
            // Still recording; the previous hotkey stays suspended until this ends.
            message = "Include Command or Control."
            return
        }
        if onRecord?(candidate) == true {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isRecording = false
            suspended = false
            binding = candidate
            isActive = true
            message = nil
        } else {
            let previousMessage = "\(candidate.displayString) is unavailable or used by another app."
            stop(restore: true)
            message = previousMessage
        }
    }
}

struct HotkeyRecorder: View {
    @ObservedObject var model: HotkeyRecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Toggle shortcut")
                Spacer()
                Button(model.isRecording ? "Recording…" : (model.isActive ? (model.binding?.displayString ?? "Record Shortcut") : "Record Shortcut")) {
                    model.toggleRecording()
                }
                if model.binding != nil {
                    Button("Clear") { model.clear() }
                }
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
