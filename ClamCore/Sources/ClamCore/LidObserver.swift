import Foundation
import IOKit

/// Reports lid open/closed from IOPMrootDomain. Main-thread only.
public final class LidObserver {
    /// Called with `true` when the lid closes and `false` when it opens.
    public var onChange: ((Bool) -> Void)?
    public private(set) var isClosed = false
    /// False on Macs without a lid.
    public private(set) var isSupported = false

    private let root: io_service_t
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0

    public init() {
        root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if let closed = readClosed() {
            isSupported = true
            isClosed = closed
        }
    }

    deinit {
        if notifier != 0 { IOObjectRelease(notifier) }
        if let port { IONotificationPortDestroy(port) }
        if root != 0 { IOObjectRelease(root) }
    }

    /// Begin delivering `onChange` on the main queue.
    public func start() {
        guard root != 0, port == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        self.port = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let callback: IOServiceInterestCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<LidObserver>.fromOpaque(context).takeUnretainedValue().refresh()
        }
        // Any general-interest message is a cue to re-read the property; duplicates are filtered below.
        let result = IOServiceAddInterestNotification(port, root, kIOGeneralInterest, callback,
                                                      Unmanaged.passUnretained(self).toOpaque(), &notifier)
        guard result == KERN_SUCCESS else {
            // Tear down so a later start() can retry from a clean state.
            IONotificationPortDestroy(port)
            self.port = nil
            notifier = 0
            return
        }
    }

    /// Re-read the lid state and report a change. Also safe to call from a timer.
    public func refresh() {
        guard let closed = readClosed(), closed != isClosed else { return }
        isClosed = closed
        onChange?(closed)
    }

    /// The kernel's reason for the most recent sleep, when it publishes one.
    public func lastSleepReason() -> String? {
        property("Last Sleep Reason") as? String
    }

    private func readClosed() -> Bool? {
        property("AppleClamshellState") as? Bool
    }

    private func property(_ key: String) -> Any? {
        guard root != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
