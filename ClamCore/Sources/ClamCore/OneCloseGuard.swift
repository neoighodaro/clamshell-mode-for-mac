import Foundation

/// Decides whether a one-close session must be cancelled even though the gesture itself cannot.
/// The controller state is the source of truth: one-close sessions are only ever created by
/// the tilt gesture, so one that nothing is tracking must not stay armed with the lid open.
public enum OneCloseGuard {
    public static func shouldCancel(oneCloseArmed: Bool, gestureArmed: Bool, preferenceOn: Bool,
                                    secondsSinceGoodSample: TimeInterval,
                                    stallSeconds: TimeInterval = TiltGesture.Config().stallSeconds) -> Bool {
        guard oneCloseArmed else { return false }
        return !gestureArmed || !preferenceOn || secondsSinceGoodSample > stallSeconds
    }
}
