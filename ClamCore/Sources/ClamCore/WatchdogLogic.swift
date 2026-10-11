import Foundation

public enum WatchdogStart: Equatable, Sendable {
    /// No pid file: the app is not running or quit cleanly.
    case exitClean
    /// Pid file from before the last reboot. The reboot cleared the flag.
    case removeStaleAndExit
    case monitor(pid: Int32)
    /// The app is gone but left its pid file. Clear the flag and recover.
    case unclean
}

public enum WatchdogExit: Equatable, Sendable {
    case clean
    case unclean
}

public enum WatchdogAction: Equatable, Sendable {
    case clearFlag
    case relaunch
    case standDown
}

/// The watchdog's decisions, separated from processes and the kernel.
public enum WatchdogLogic {
    public static func onStart(pidFileExists: Bool, record: PidRecord?, currentBootSession: String?,
                               isClam: (PidRecord) -> Bool) -> WatchdogStart {
        guard pidFileExists else { return .exitClean }
        guard let record else { return .unclean }
        if let currentBootSession, record.bootSession != currentBootSession {
            return .removeStaleAndExit
        }
        return isClam(record) ? .monitor(pid: record.pid) : .unclean
    }

    public static func onAppExit(pidFileExists: Bool) -> WatchdogExit {
        pidFileExists ? .unclean : .clean
    }

    /// The actions to run, in order. The flag clear comes first on every path: recovery
    /// must not depend on the relaunched app surviving long enough to do it.
    public static func afterUncleanExit(guardStandsDown: Bool) -> [WatchdogAction] {
        [.clearFlag, guardStandsDown ? .standDown : .relaunch]
    }

    public static func matchesClam(record: PidRecord, alive: Bool, startTime: Double?, path: String?) -> Bool {
        guard alive, let startTime, let path else { return false }
        guard abs(startTime - record.startTime) < 1 else { return false }
        return path.hasSuffix("/Contents/MacOS/Clam")
    }
}
