import Foundation

public enum SessionEvent: Equatable, Sendable {
    /// Menu, right-click, hotkey, Toggle intent.
    case toggle
    /// Arm intent or the menu's Arm item.
    case arm
    case disarm
    case tiltArm
    case tiltCancel
    case lidClosed
    case lidOpened
    /// Battery, thermal, display topology or rival state changed.
    case environmentChanged
    case systemWillSleep
    case systemDidWake
    /// Display slept, display woke, or the power source changed.
    case reapplyTrigger
    /// Clamshell.app launched.
    case rivalLaunched
}

public enum SessionNotice: Equatable, Sendable {
    case armFailed
    case armBlocked(SafetyReason)
    case forcedDisarm(SafetyReason)
    case reapplyFailed
    case clearFailed
    case clearRecovered
    case pausedForExternalDisplay
    case resumeFailed
    case sessionInterrupted(reason: String?)
    case rivalLaunched
}

public struct SessionSettings: Equatable, Sendable {
    public var screenMode: ScreenMode
    public var safety: SafetySettings

    public init(screenMode: ScreenMode = .displayOff, safety: SafetySettings = SafetySettings()) {
        self.screenMode = screenMode
        self.safety = safety
    }
}

/// The session state machine. Main-thread only.
/// Sets and clears the sleep flag for a session and holds the keep-awake and transition
/// assertions. Outside it, `ScreenController` holds the display assertion, and the app clears
/// the flag once at launch and takes the transition guard at quit.
public final class SessionController {
    public static let clearRetrySeconds: TimeInterval = 5
    public static let transitionGuardSeconds: TimeInterval = 10

    public private(set) var state: SessionState = .disarmed {
        didSet {
            if state != oldValue { onStateChange?(oldValue, state) }
        }
    }
    /// A disarm could not clear the kernel flag; a retry is scheduled.
    public private(set) var clearPending = false
    /// On a disarm this fires before the flag is cleared. It must not call back into `handle`.
    public var onStateChange: ((SessionState, SessionState) -> Void)?
    public var onNotice: ((SessionNotice) -> Void)?

    private let flag: SleepFlagControlling
    private let assertions: PowerAsserting
    private let screen: ScreenControlling
    private let scheduler: Scheduling
    private let environment: () -> Environment
    private let settings: () -> SessionSettings
    private let sleepReason: () -> String?

    private var clearTimer: Cancellable?
    private var guardTimer: Cancellable?
    private var sleptWhileClosed = false
    private var isShutDown = false

    public init(flag: SleepFlagControlling, assertions: PowerAsserting, screen: ScreenControlling,
                scheduler: Scheduling, environment: @escaping () -> Environment,
                settings: @escaping () -> SessionSettings, sleepReason: @escaping () -> String?) {
        self.flag = flag
        self.assertions = assertions
        self.screen = screen
        self.scheduler = scheduler
        self.environment = environment
        self.settings = settings
        self.sleepReason = sleepReason
    }

    public func handle(_ event: SessionEvent) {
        guard !isShutDown else { return }
        switch event {
        case .toggle:
            if state == .disarmed { arm(.persistent) } else { dropSession() }
        case .arm:
            explicitArm()
        case .disarm:
            if state != .disarmed { dropSession() }
        case .tiltArm:
            if state == .disarmed, environment().externalDisplay == false { arm(.oneClose) }
        case .tiltCancel:
            if state == .armed(.oneClose) { dropSession() }
        case .lidClosed:
            lidClosed()
        case .lidOpened:
            lidOpened()
        case .reapplyTrigger:
            reapply()
        case .environmentChanged:
            reevaluate()
        case .systemWillSleep:
            if case .closed = state { sleptWhileClosed = true }
        case .systemDidWake:
            didWake()
        case .rivalLaunched:
            if state != .disarmed {
                notify(.rivalLaunched)
                dropSession()
            }
        }
    }

    /// Retry a failed clear now. Used by the menu's Retry item.
    public func retryClear() {
        if clearPending, !isShutDown, !state.isArmedOrClosed { clearFlag() }
    }

    /// Launch-time clear that failed before this controller existed: runs the same
    /// notice-and-retry path as a failed disarm. Skipped while the rival app is running.
    public func clearAtLaunch() {
        if !isShutDown, state == .disarmed, !environment().rivalRunning { clearFlag() }
    }

    /// Final clear on quit. Returns whether the kernel accepted it. Later events are ignored.
    /// The transition guard is left alone: the caller holds it until the pid file is
    /// removed, and process exit releases it.
    public func shutdown() -> Bool {
        isShutDown = true
        cancelTimers()
        assertions.setKeepAwake(false)
        assertions.setDisplayAwake(false)
        state = .disarmed
        return flag.set(disabled: false)
    }

    // MARK: Arming

    private func explicitArm() {
        switch state {
        case .disarmed: arm(.persistent)
        case .armed(.oneClose): state = .armed(.persistent)
        case .closed(.oneClose): state = .closed(.persistent)
        case .armed(.persistent), .closed(.persistent), .paused: break
        }
    }

    private func arm(_ mode: ArmMode) {
        let env = environment()
        switch SafetyPolicy.evaluate(state: .disarmed, environment: env, settings: settings().safety) {
        case .blockArm(let reason), .forceDisarm(let reason):
            notify(.armBlocked(reason))
            return
        case .pause:
            guard mode == .persistent else { return }
            state = .paused
            notify(.pausedForExternalDisplay)
            return
        case .allow:
            break
        }
        guard flag.set(disabled: true) else {
            notify(.armFailed)
            return
        }
        clearTimer?.cancel()
        clearTimer = nil
        clearPending = false
        sleptWhileClosed = false
        assertions.setKeepAwake(true)
        if env.lidClosed {
            enterClosed(mode)
        } else {
            state = .armed(mode)
        }
    }

    private func enterClosed(_ mode: ArmMode) {
        pulseTransitionGuard()
        state = .closed(mode)
        screen.lidClosed(mode: settings().screenMode)
    }

    // MARK: Lid

    private func lidClosed() {
        guard case .armed(let mode) = state else { return }
        enterClosed(mode)
    }

    private func lidOpened() {
        if sleptWhileClosed, state.isArmedOrClosed {
            sleptWhileClosed = false
            notify(.sessionInterrupted(reason: sleepReason()))
            dropSession()
            screen.processPendingRestore(lidOpen: true)
            return
        }
        switch state {
        case .closed(.persistent):
            pulseTransitionGuard()
            state = .armed(.persistent)
        case .closed(.oneClose):
            dropSession()
        case .disarmed, .armed, .paused:
            break
        }
        // Undo is driven by the record on disk, not by session state.
        screen.processPendingRestore(lidOpen: true)
    }

    // MARK: Safety

    private func reevaluate() {
        if state == .disarmed { return }
        let verdict = SafetyPolicy.evaluate(state: state, environment: environment(),
                                            settings: settings().safety)
        switch (state, verdict) {
        case (.paused, .forceDisarm(let reason)):
            // The flag is already clear; this cancels the automatic re-arm.
            notify(.forcedDisarm(reason))
            state = .disarmed
        case (.paused, .allow):
            resume()
        case (.paused, _):
            break
        case (_, .forceDisarm(let reason)), (_, .blockArm(let reason)):
            // Notify before the clear: with the lid shut the Mac sleeps right after it.
            notify(.forcedDisarm(reason))
            dropSession()
        case (.armed(.persistent), .pause), (.closed(.persistent), .pause):
            notify(.pausedForExternalDisplay)
            dropSession(to: .paused)
        case (.armed(.oneClose), .pause), (.closed(.oneClose), .pause):
            dropSession()
        default:
            break
        }
    }

    private func resume() {
        let env = environment()
        assertions.setTransitionGuard(true)
        guard flag.set(disabled: true) else {
            assertions.setTransitionGuard(false)
            state = .disarmed
            notify(.resumeFailed)
            return
        }
        clearTimer?.cancel()
        clearTimer = nil
        clearPending = false
        sleptWhileClosed = false
        assertions.setKeepAwake(true)
        if env.lidClosed {
            enterClosed(.persistent)
        } else {
            pulseTransitionGuard()
            state = .armed(.persistent)
        }
    }

    // MARK: Sleep

    private func didWake() {
        if sleptWhileClosed {
            sleptWhileClosed = false
            if state.isArmedOrClosed {
                notify(.sessionInterrupted(reason: sleepReason()))
                dropSession()
            }
        } else {
            reapply()
        }
        screen.processPendingRestore(lidOpen: !environment().lidClosed)
    }

    /// Hold PreventSystemSleep across a lid transition, then re-apply the flag
    /// in case releasing the assertion made powerd rewrite it.
    private func pulseTransitionGuard() {
        assertions.setTransitionGuard(true)
        guardTimer?.cancel()
        guardTimer = scheduler.schedule(after: Self.transitionGuardSeconds) { [weak self] in
            guard let self else { return }
            self.guardTimer = nil
            self.assertions.setTransitionGuard(false)
            self.reapply()
        }
    }

    private func reapply() {
        guard state.isArmedOrClosed else { return }
        if !flag.set(disabled: true) {
            notify(.reapplyFailed)
            dropSession()
        }
    }

    // MARK: Disarming

    /// End the session: release assertions, change state, then clear the flag last.
    /// With the lid shut, the Mac sleeps as soon as the flag clears.
    private func dropSession(to newState: SessionState = .disarmed) {
        guardTimer?.cancel()
        guardTimer = nil
        // A sleep seen by this session says nothing about the next one.
        sleptWhileClosed = false
        assertions.setKeepAwake(false)
        // Agents-screen mode holds this while closed. A session that ends without a
        // lid open (pause, forced disarm) must not keep the display from idle-sleeping.
        assertions.setDisplayAwake(false)
        state = newState
        clearFlag()
        assertions.setTransitionGuard(false)
    }

    private func clearFlag() {
        clearTimer?.cancel()
        clearTimer = nil
        if flag.set(disabled: false) {
            if clearPending {
                clearPending = false
                notify(.clearRecovered)
            }
            return
        }
        if !clearPending {
            clearPending = true
            notify(.clearFailed)
        }
        scheduleClearRetry()
    }

    private func scheduleClearRetry() {
        clearTimer = scheduler.schedule(after: Self.clearRetrySeconds) { [weak self] in
            guard let self, self.clearPending, !self.state.isArmedOrClosed else { return }
            // The rival owns the setting while it runs; keep the retry alive without touching it.
            if self.environment().rivalRunning { self.scheduleClearRetry() } else { self.clearFlag() }
        }
    }

    private func cancelTimers() {
        clearTimer?.cancel()
        clearTimer = nil
        guardTimer?.cancel()
        guardTimer = nil
    }

    private func notify(_ notice: SessionNotice) {
        onNotice?(notice)
    }
}
