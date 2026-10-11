import AppKit
import ClamCore

/// Polls the lid angle and drives the one-close gesture. Main-thread only.
/// Polling runs while the "tilt gesture" preference is on (see `apply()`), and also while a
/// one-close session is armed, so a stranded session is always cancelled.
final class TiltMonitor {
    private let sensor = LidAngleSensor()
    private let controller: SessionController
    private let preferences: Preferences
    private let monitor: EnvironmentMonitor
    private var gesture = TiltGesture()
    private var timer: Timer?
    /// Last time the sensor gave a reading (or the last tick with no one-close session).
    private var lastGoodSample: TimeInterval = 0
    /// Set by the app while it is quitting; the gesture then does nothing.
    var isTerminating: () -> Bool = { false }

    init(controller: SessionController, preferences: Preferences, monitor: EnvironmentMonitor) {
        self.controller = controller
        self.preferences = preferences
        self.monitor = monitor
    }

    private var oneCloseArmed: Bool { controller.state == .armed(.oneClose) }

    /// Starts or stops polling to match the preference. Safe to call at any time.
    func apply() {
        if preferences.tiltGestureEnabled { start() } else { stop() }
    }

    func start() {
        guard sensor.isAvailable, timer == nil else { return }
        lastGoodSample = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.05
        // Common modes, so the gesture keeps working while a status menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the gesture. A one-close session is cancelled first (the controller ignores the
    /// event in any other state); the timer keeps running until it has been.
    func stop() {
        gesture.reset()
        if oneCloseArmed, !isTerminating() { monitor.onEvent?(.tiltCancel) }
        if !oneCloseArmed {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        if isTerminating() { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !oneCloseArmed { lastGoodSample = now }

        // The controller state is the source of truth for a one-close session.
        if OneCloseGuard.shouldCancel(oneCloseArmed: oneCloseArmed, gestureArmed: gesture.isArmed,
                                      preferenceOn: preferences.tiltGestureEnabled,
                                      secondsSinceGoodSample: now - lastGoodSample) {
            gesture.reset()
            monitor.onEvent?(.tiltCancel)
            return
        }
        // Preference off and nothing left to cancel: stop polling.
        if !preferences.tiltGestureEnabled {
            stop()
            return
        }

        let state = controller.state
        let eligible = !monitor.lid.isClosed && (state == .disarmed || state == .armed(.oneClose))
        guard eligible else {
            gesture.reset()
            return
        }
        // The user disarmed some other way mid-gesture: start over.
        if state == .disarmed, gesture.isArmed {
            gesture.reset()
        }
        guard let angle = sensor.angle() else {
            // A missed sample must not make the next one look like a crossing.
            gesture.forgetAngle()
            return
        }
        lastGoodSample = now
        let optionHeld = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)

        // Monotonic seconds: unaffected by wall-clock changes.
        switch gesture.sample(angle: angle, optionHeld: optionHeld, at: now) {
        case .armOneClose:
            // Same path as the hotkey: the environment is refreshed before the controller sees it.
            monitor.onEvent?(.tiltArm)
            // Arming may be blocked by a safety or an external display.
            if controller.state != .armed(.oneClose) { gesture.reset() }
        case .cancel:
            monitor.onEvent?(.tiltCancel)
        case .none:
            break
        }
    }
}
