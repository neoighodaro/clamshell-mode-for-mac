import Foundation

/// Turns lid-angle samples and Option-key state into one-close arming decisions.
public struct TiltGesture {
    public enum Decision: Equatable, Sendable {
        case none
        case armOneClose
        case cancel
    }

    public struct Config: Sendable {
        public var activationDegrees = 60
        public var reverseCancelDegrees = 20
        public var stallSeconds: TimeInterval = 10
        public init() {}
    }

    public private(set) var isArmed = false
    private let config: Config
    private var lastAngle: Int?
    private var mostClosedAngle = 0
    private var lastProgress: TimeInterval = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    /// `time` is seconds on a monotonic clock (for example `ProcessInfo.systemUptime`), never wall-clock time.
    public mutating func sample(angle: Int, optionHeld: Bool, at time: TimeInterval) -> Decision {
        defer { lastAngle = angle }

        // Checked before the previous angle is needed: an armed gesture must still stall
        // or reverse out when samples are being missed.
        if isArmed {
            if angle < mostClosedAngle {
                mostClosedAngle = angle
                lastProgress = time
            }
            if angle - mostClosedAngle >= config.reverseCancelDegrees || time - lastProgress >= config.stallSeconds {
                isArmed = false
                return .cancel
            }
            return .none
        }

        guard let previous = lastAngle else { return .none }
        let crossed = previous >= config.activationDegrees && angle < config.activationDegrees
        guard crossed, optionHeld else { return .none }
        isArmed = true
        mostClosedAngle = angle
        lastProgress = time
        return .armOneClose
    }

    /// A sample was missed: the next one must not be compared with an angle from before the gap.
    /// Leaves an armed gesture armed.
    public mutating func forgetAngle() {
        lastAngle = nil
    }

    public mutating func reset() {
        isArmed = false
        lastAngle = nil
    }
}
