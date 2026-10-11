import Foundation

public enum ScreenNotice: Equatable, Sendable {
    case displayMayStayLit
    case agentsScreenUnavailable
    case couldNotPersist
    /// Agents-screen mode was asked for before a lock had been verified on this Mac.
    case lockNotVerified
    case darkenFailed
    case lockUnconfirmed
    case restoreFailed
}

/// Applies the closed-lid screen mode and undoes it from the record on disk.
public final class ScreenController: ScreenControlling {
    public static let lockPollSeconds: TimeInterval = 0.1
    public static let lockPollLimit = 30   // 3 seconds
    public static let restoreRetrySeconds: TimeInterval = 1
    public static let restoreRetryLimit = 10

    public var onNotice: ((ScreenNotice) -> Void)?

    private let brightness: BrightnessControlling
    private let locker: SessionLocking
    private let sleeper: DisplaySleeping
    private let store: RestoreRecordStore
    private let assertions: PowerAsserting
    private let scheduler: Scheduling
    private let lockVerified: () -> Bool

    private var restoring = false
    /// Bumped whenever a restore is superseded, so stale polls stop.
    private var generation = 0
    private var completions: [() -> Void] = []

    public init(brightness: BrightnessControlling, locker: SessionLocking, sleeper: DisplaySleeping,
                store: RestoreRecordStore, assertions: PowerAsserting, scheduler: Scheduling,
                lockVerified: @escaping () -> Bool) {
        self.brightness = brightness
        self.locker = locker
        self.sleeper = sleeper
        self.store = store
        self.assertions = assertions
        self.scheduler = scheduler
        self.lockVerified = lockVerified
    }

    public func lidClosed(mode: ScreenMode) {
        // A restore still waiting for the lock is abandoned; its record stays.
        generation += 1
        restoring = false
        let pending = completions
        completions.removeAll()
        pending.forEach { $0() }

        switch mode {
        case .displayOff:
            sleepDisplay()
        case .agentsScreen:
            // The mode leaves the screen on and relies on locking at lid open. Until a lock
            // has been seen to work here, it is display off.
            if lockVerified() {
                darken()
            } else {
                onNotice?(.lockNotVerified)
                sleepDisplay()
            }
        }
    }

    public func processPendingRestore(lidOpen: Bool) {
        processPendingRestore(lidOpen: lidOpen, completion: nil)
    }

    /// `completion` runs when the restore finishes, or at once if there is nothing to do.
    public func processPendingRestore(lidOpen: Bool, completion: (() -> Void)?) {
        guard lidOpen, let record = store.load() else {
            completion?()
            return
        }
        if let completion { completions.append(completion) }
        guard !restoring else { return }

        restoring = true
        generation += 1
        assertions.setDisplayAwake(false)
        guard record.lockOwed else {
            finish(record, lockConfirmed: true)
            return
        }
        _ = locker.requestLock()
        poll(generation: generation, record: record, attempt: 0)
    }

    private func sleepDisplay() {
        if sleeper.sleepDisplay() { return }
        if sleeper.sleepDisplay() { return }
        onNotice?(.displayMayStayLit)
    }

    private func darken() {
        guard brightness.isAvailable else {
            onNotice?(.agentsScreenUnavailable)
            sleepDisplay()
            return
        }
        // Keep an existing record: it holds the brightness from before the first darkening.
        if !store.exists {
            // With the lid shutting, the read can come back dark or not at all. Restoring
            // to that would leave the screen black, so a visible level is saved instead.
            let current = RestoreRecordStore.usableBrightness(brightness.get())
            do {
                try store.save(RestoreRecord(brightness: current, lockOwed: true))
            } catch {
                // Not darkened and no lock owed: the screen must not stay lit and unlocked.
                onNotice?(.couldNotPersist)
                sleepDisplay()
                return
            }
        }
        _ = brightness.set(0)
        if (brightness.get() ?? 1) > 0.01 {
            onNotice?(.darkenFailed)
        }
        assertions.setDisplayAwake(true)
    }

    private func poll(generation expected: Int, record: RestoreRecord, attempt: Int) {
        guard expected == generation else { return }
        if locker.isLocked {
            finish(record, lockConfirmed: true)
            return
        }
        if attempt >= Self.lockPollLimit {
            finish(record, lockConfirmed: false)
            return
        }
        scheduler.schedule(after: Self.lockPollSeconds) { [weak self] in
            self?.poll(generation: expected, record: record, attempt: attempt + 1)
        }
    }

    private func finish(_ record: RestoreRecord, lockConfirmed: Bool, attempt: Int = 0) {
        if brightness.set(record.brightness) {
            store.delete()
        } else if attempt < Self.restoreRetryLimit {
            // The built-in display may not be back yet. `restoring` stays true meanwhile.
            let expected = generation
            scheduler.schedule(after: Self.restoreRetrySeconds) { [weak self] in
                guard let self, expected == self.generation else { return }
                self.finish(record, lockConfirmed: lockConfirmed, attempt: attempt + 1)
            }
            return
        } else {
            // The record stays; the next lid open, wake or launch tries again.
            onNotice?(.restoreFailed)
        }
        restoring = false
        if !lockConfirmed {
            onNotice?(.lockUnconfirmed)
        }
        let pending = completions
        completions.removeAll()
        pending.forEach { $0() }
    }
}
