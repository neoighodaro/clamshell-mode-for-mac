import Foundation

/// Proves that Clam can lock this Mac, by locking it once and watching for the lock.
/// Agents-screen mode is offered only after this has succeeded. Main-thread only.
public final class LockVerifier {
    private let locker: SessionLocking
    private let scheduler: Scheduling
    private var completions: [(Bool) -> Void] = []

    public init(locker: SessionLocking, scheduler: Scheduling) {
        self.locker = locker
        self.scheduler = scheduler
    }

    /// Requests the lock screen and reports whether the session locked within the time the
    /// lid-open restore allows. A request that cannot be sent fails at once.
    /// A call made while a check is running shares that check's result.
    public func verify(completion: @escaping (Bool) -> Void) {
        completions.append(completion)
        guard completions.count == 1 else { return }
        guard locker.requestLock() else {
            finish(false)
            return
        }
        poll(attempt: 0)
    }

    private func poll(attempt: Int) {
        if locker.isLocked {
            finish(true)
            return
        }
        if attempt >= ScreenController.lockPollLimit {
            finish(false)
            return
        }
        scheduler.schedule(after: ScreenController.lockPollSeconds) { [weak self] in
            self?.poll(attempt: attempt + 1)
        }
    }

    private func finish(_ locked: Bool) {
        let pending = completions
        completions.removeAll()
        pending.forEach { $0(locked) }
    }
}
