import Foundation
@testable import ClamCore

final class FakeFlag: SleepFlagControlling {
    var setSucceeds = true
    var clearSucceeds = true
    var calls: [Bool] = []
    /// What the kernel flag would be, given which calls succeeded.
    var isSet = false

    func set(disabled: Bool) -> Bool {
        calls.append(disabled)
        let ok = disabled ? setSucceeds : clearSucceeds
        if ok { isSet = disabled }
        return ok
    }
}

final class FakeAssertions: PowerAsserting {
    var keepAwake = false
    var transitionGuard = false
    var displayAwake = false
    func setKeepAwake(_ on: Bool) { keepAwake = on }
    func setTransitionGuard(_ on: Bool) { transitionGuard = on }
    func setDisplayAwake(_ on: Bool) { displayAwake = on }
}

final class FakeScreen: ScreenControlling {
    var closedModes: [ScreenMode] = []
    var restoreCalls: [Bool] = []
    func lidClosed(mode: ScreenMode) { closedModes.append(mode) }
    func processPendingRestore(lidOpen: Bool) { restoreCalls.append(lidOpen) }
}

final class ManualScheduler: Scheduling {
    final class Job: Cancellable {
        let due: TimeInterval
        let work: () -> Void
        var cancelled = false
        init(due: TimeInterval, work: @escaping () -> Void) {
            self.due = due
            self.work = work
        }
        func cancel() { cancelled = true }
    }

    var now: TimeInterval = 0
    private var jobs: [Job] = []

    @discardableResult
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        let job = Job(due: now + seconds, work: work)
        jobs.append(job)
        return job
    }

    /// Runs every job that falls due, in order, including jobs scheduled by other jobs.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = jobs.filter({ !$0.cancelled && $0.due <= target }).min(by: { $0.due < $1.due }) {
            now = next.due
            jobs.removeAll { $0 === next }
            next.work()
        }
        jobs.removeAll { $0.cancelled }
        now = target
    }
}

/// A SessionController wired to fakes.
final class Harness {
    let flag = FakeFlag()
    let assertions = FakeAssertions()
    let screen = FakeScreen()
    let scheduler = ManualScheduler()
    var env = Environment.nominal
    var settings = SessionSettings()
    var sleepReason: String?
    var notices: [SessionNotice] = []
    var transitions: [SessionState] = []

    lazy var controller: SessionController = {
        let c = SessionController(
            flag: flag, assertions: assertions, screen: screen, scheduler: scheduler,
            environment: { [unowned self] in self.env },
            settings: { [unowned self] in self.settings },
            sleepReason: { [unowned self] in self.sleepReason })
        c.onNotice = { [unowned self] in self.notices.append($0) }
        c.onStateChange = { [unowned self] _, new in self.transitions.append(new) }
        return c
    }()

    func send(_ events: SessionEvent...) {
        for e in events { controller.handle(e) }
    }
}

final class FakeBrightness: BrightnessControlling {
    var isAvailable = true
    var value: Float? = 0.8
    var setSucceeds = true
    var sets: [Float] = []
    func get() -> Float? { value }
    func set(_ newValue: Float) -> Bool {
        sets.append(newValue)
        if setSucceeds { value = newValue }
        return setSucceeds
    }
}

final class FakeLocker: SessionLocking {
    var requests = 0
    var isLocked = false
    /// When true, a lock request locks the session immediately.
    var locksOnRequest = false
    var requestSucceeds = true
    func requestLock() -> Bool {
        requests += 1
        if locksOnRequest { isLocked = true }
        return requestSucceeds
    }
}

final class FakeSleeper: DisplaySleeping {
    var results: [Bool] = []
    var calls = 0
    func sleepDisplay() -> Bool {
        calls += 1
        return results.isEmpty ? true : results.removeFirst()
    }
}

func temporaryFile(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clam-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}
