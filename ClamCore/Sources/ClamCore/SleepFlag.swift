import ClamSignal
import Foundation
import IOKit

/// The kernel's lid-close sleep flag, set through IOPMrootDomain's user client.
/// One global bit: not per process, not readable, cleared only by a call or a reboot.
public final class SleepFlag: SleepFlagControlling {
    /// kPMSetClamshellSleepState.
    private static let selector: UInt32 = 12

    private let connection: io_connect_t
    private var published = false

    /// Fails if the root-domain connection cannot be opened.
    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var opened: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &opened) == KERN_SUCCESS else { return nil }
        connection = opened
    }

    deinit {
        if published { clam_signal_set_connection(0) }
        IOServiceClose(connection)
    }

    /// `true` stops the Mac sleeping when the lid closes; `false` restores it.
    /// The return code is the only evidence that it took effect.
    public func set(disabled: Bool) -> Bool {
        var value: UInt64 = disabled ? 1 : 0
        return IOConnectCallScalarMethod(connection, Self.selector, &value, 1, nil, nil) == KERN_SUCCESS
    }

    /// Let the signal handlers clear the flag through this connection.
    public func publishToSignalHandlers() {
        clam_signal_set_connection(connection)
        published = true
    }

    /// Open a connection, clear the flag, close. Used by the watchdog.
    public static func clearOnce() -> Bool {
        guard let flag = SleepFlag() else { return false }
        return flag.set(disabled: false)
    }
}
