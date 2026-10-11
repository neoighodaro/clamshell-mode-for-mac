import Foundation

public enum SafetyReason: Equatable, Sendable {
    case thermal
    case lowBattery(percent: Int)
    case batteryUnreadable
    case topologyUnreadable
    case rivalRunning
}

public enum SafetyVerdict: Equatable, Sendable {
    case allow
    case blockArm(SafetyReason)
    case forceDisarm(SafetyReason)
    case pause
}

public enum SafetyPolicy {
    public static func evaluate(state: SessionState, environment env: Environment,
                                settings: SafetySettings) -> SafetyVerdict {
        if let reason = hazard(env, settings) {
            return state == .disarmed ? .blockArm(reason) : .forceDisarm(reason)
        }
        if env.externalDisplay == nil {
            switch state {
            case .disarmed: return .blockArm(.topologyUnreadable)
            case .paused: return .pause
            case .armed, .closed: return .forceDisarm(.topologyUnreadable)
            }
        }
        if state == .disarmed, env.rivalRunning {
            return .blockArm(.rivalRunning)
        }
        if env.externalDisplay == true {
            return .pause
        }
        return .allow
    }

    private static func hazard(_ env: Environment, _ settings: SafetySettings) -> SafetyReason? {
        if env.thermal >= .serious { return .thermal }
        guard settings.batterySafetyEnabled else { return nil }
        if env.batteryMissingSamples >= 2 { return .batteryUnreadable }
        if env.onBattery, let percent = env.batteryPercent, percent <= settings.batteryThreshold {
            return .lowBattery(percent: percent)
        }
        return nil
    }
}
