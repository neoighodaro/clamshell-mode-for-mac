import Foundation

public enum ArmMode: Equatable, Sendable {
    case persistent
    case oneClose
}

public enum SessionState: Equatable, Sendable {
    case disarmed
    case armed(ArmMode)
    case closed(ArmMode)
    case paused

    public var isArmedOrClosed: Bool {
        switch self {
        case .armed, .closed: return true
        case .disarmed, .paused: return false
        }
    }
}

public enum ScreenMode: String, Sendable, CaseIterable {
    case displayOff
    case agentsScreen
}

public enum ThermalLevel: Int, Sendable, Comparable {
    case nominal, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A snapshot of everything outside Clam that the state machine reads.
public struct Environment: Equatable, Sendable {
    public var lidClosed: Bool
    /// `nil` means the display list could not be read.
    public var externalDisplay: Bool?
    public var onBattery: Bool
    /// `nil` means the battery percentage could not be read.
    public var batteryPercent: Int?
    /// Consecutive samples in which `batteryPercent` was `nil`.
    public var batteryMissingSamples: Int
    public var thermal: ThermalLevel
    /// Clamshell.app (`com.rathonyi.clamshell`) is running.
    public var rivalRunning: Bool

    public init(lidClosed: Bool, externalDisplay: Bool?, onBattery: Bool, batteryPercent: Int?,
                batteryMissingSamples: Int, thermal: ThermalLevel, rivalRunning: Bool) {
        self.lidClosed = lidClosed
        self.externalDisplay = externalDisplay
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.batteryMissingSamples = batteryMissingSamples
        self.thermal = thermal
        self.rivalRunning = rivalRunning
    }

    /// Lid open, on AC, 80%, cool, no external display, no rival.
    public static let nominal = Environment(
        lidClosed: false, externalDisplay: false, onBattery: false, batteryPercent: 80,
        batteryMissingSamples: 0, thermal: .nominal, rivalRunning: false)
}

public struct SafetySettings: Equatable, Sendable {
    public static let thresholdRange = 5...50

    public var batterySafetyEnabled: Bool
    public private(set) var batteryThreshold: Int

    public init(batterySafetyEnabled: Bool = true, batteryThreshold: Int = 20) {
        self.batterySafetyEnabled = batterySafetyEnabled
        self.batteryThreshold = min(max(batteryThreshold, Self.thresholdRange.lowerBound),
                                    Self.thresholdRange.upperBound)
    }
}

extension ThermalLevel {
    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}
