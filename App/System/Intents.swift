import AppIntents
import ClamCore

enum ClamIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case armRefused
    case armPaused
    case disarmIncomplete

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            return "Clam is still starting. Try again in a moment."
        case .armRefused:
            return "Clam did not arm. A safety check (battery, temperature, display state or Clamshell.app) is blocking it, or macOS refused the change."
        case .armPaused:
            return "Clam is paused because an external display is connected, so the Mac will still sleep when the lid closes. Clam arms by itself if the display is unplugged."
        case .disarmIncomplete:
            return "Clam could not restore normal lid sleep yet and will retry. Check Clam's menu."
        }
    }
}

/// Sends the event down the same path as the menu and the hotkey (environment refresh, then the
/// controller) and returns the resulting state. Throws until the app has finished launching.
@MainActor
private func send(_ event: SessionEvent) throws -> (controller: SessionController, before: SessionState) {
    guard let delegate = AppDelegate.shared, let controller = delegate.controller,
          let before = delegate.dispatch(event)
    else { throw ClamIntentError.notReady }
    return (controller, before)
}

private func describe(_ state: SessionState) -> String {
    switch state {
    case .disarmed: return "Disarmed"
    case .armed(.persistent): return "Armed"
    case .armed(.oneClose): return "Armed for one close"
    case .closed: return "Running with the lid closed"
    case .paused: return "Paused for an external display"
    }
}

struct ArmClamIntent: AppIntent {
    static var title: LocalizedStringResource = "Arm Clam"
    static var description = IntentDescription("Keep this Mac awake when the lid closes.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (controller, _) = try send(.arm)
        // Still disarmed: the safety policy refused, or the kernel flag could not be set.
        if controller.state == .disarmed { throw ClamIntentError.armRefused }
        if controller.state == .paused { throw ClamIntentError.armPaused }
        return .result(value: describe(controller.state))
    }
}

struct DisarmClamIntent: AppIntent {
    static var title: LocalizedStringResource = "Disarm Clam"
    static var description = IntentDescription("Let this Mac sleep when the lid closes.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (controller, _) = try send(.disarm)
        if controller.state != .disarmed || controller.clearPending { throw ClamIntentError.disarmIncomplete }
        return .result(value: describe(controller.state))
    }
}

struct ToggleClamIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Clam"
    static var description = IntentDescription("Arm Clam if it is disarmed; otherwise disarm it.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (controller, before) = try send(.toggle)
        if before == .disarmed {
            if controller.state == .disarmed { throw ClamIntentError.armRefused }
            if controller.state == .paused { throw ClamIntentError.armPaused }
        } else if controller.state != .disarmed || controller.clearPending {
            throw ClamIntentError.disarmIncomplete
        }
        return .result(value: describe(controller.state))
    }
}

struct ClamStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Clam Status"
    static var description = IntentDescription("Report whether Clam is armed.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let controller = AppDelegate.shared?.controller else { throw ClamIntentError.notReady }
        return .result(value: describe(controller.state))
    }
}

struct ClamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ArmClamIntent(), phrases: ["Arm \(.applicationName)"],
                    shortTitle: "Arm", systemImageName: "lock.laptopcomputer")
        AppShortcut(intent: DisarmClamIntent(), phrases: ["Disarm \(.applicationName)"],
                    shortTitle: "Disarm", systemImageName: "laptopcomputer")
        AppShortcut(intent: ToggleClamIntent(), phrases: ["Toggle \(.applicationName)"],
                    shortTitle: "Toggle", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: ClamStatusIntent(), phrases: ["Get \(.applicationName) status"],
                    shortTitle: "Status", systemImageName: "info.circle")
    }
}
