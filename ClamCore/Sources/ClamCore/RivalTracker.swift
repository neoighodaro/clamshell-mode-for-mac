import Foundation

/// Turns repeated "is Clamshell.app running" readings into launch edges, so a launch is
/// reported exactly once however many sources notice it.
public struct RivalTracker {
    private var running: Bool?

    public init() {}

    /// Records a reading. Returns `true` when the rival has started since the previous one.
    /// The first reading only sets the baseline: a rival already running is not a launch.
    public mutating func update(running now: Bool) -> Bool {
        defer { running = now }
        return running == false && now
    }
}
