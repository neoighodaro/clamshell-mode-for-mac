import Foundation

/// The kernel lid-sleep flag. `set(disabled: true)` stops lid-close sleep.
public protocol SleepFlagControlling: AnyObject {
    func set(disabled: Bool) -> Bool
}

public protocol PowerAsserting: AnyObject {
    /// PreventUserIdleSystemSleep, held while armed.
    func setKeepAwake(_ on: Bool)
    /// PreventSystemSleep, held around lid transitions and quit.
    func setTransitionGuard(_ on: Bool)
    /// PreventUserIdleDisplaySleep, held in agents-screen mode.
    func setDisplayAwake(_ on: Bool)
}

public protocol ScreenControlling: AnyObject {
    func lidClosed(mode: ScreenMode)
    /// Undo any pending restore. Does nothing unless `lidOpen` and a record exists.
    func processPendingRestore(lidOpen: Bool)
}

public protocol Cancellable: AnyObject {
    func cancel()
}

public protocol Scheduling: AnyObject {
    @discardableResult
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> Cancellable
}

public protocol BrightnessControlling: AnyObject {
    var isAvailable: Bool { get }
    func get() -> Float?
    func set(_ value: Float) -> Bool
}

public protocol SessionLocking: AnyObject {
    /// Ask macOS to show the lock screen. Returns whether the request was sent.
    func requestLock() -> Bool
    var isLocked: Bool { get }
}

public protocol DisplaySleeping: AnyObject {
    func sleepDisplay() -> Bool
}

/// Runs work on the main queue. All ClamCore state is main-thread only.
public final class MainQueueScheduler: Scheduling {
    private final class Item: Cancellable {
        let work: DispatchWorkItem
        init(_ work: DispatchWorkItem) { self.work = work }
        func cancel() { work.cancel() }
    }

    public init() {}

    @discardableResult
    public func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return Item(item)
    }
}
