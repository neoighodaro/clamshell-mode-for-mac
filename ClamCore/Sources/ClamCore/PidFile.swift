import Darwin
import Foundation

public struct PidRecord: Codable, Equatable, Sendable {
    public var pid: Int32
    /// Process start time, seconds since 1970. Guards against pid reuse.
    public var startTime: Double
    /// `kern.bootsessionuuid` at the time of writing.
    public var bootSession: String

    public init(pid: Int32, startTime: Double, bootSession: String) {
        self.pid = pid
        self.startTime = startTime
        self.bootSession = bootSession
    }
}

/// Present while the app is running; removed only on a clean exit with the flag cleared.
public final class PidFile {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func read() -> PidRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PidRecord.self, from: data)
    }

    public func write(_ record: PidRecord) throws {
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

public enum ProcessInspector {
    public static func isAlive(_ pid: pid_t) -> Bool {
        // kill(0, _) and kill(-1, _) address process groups or every process, not one pid.
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public static func startTime(of pid: pid_t) -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        guard tv.tv_sec != 0 else { return nil }
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
    }

    public static func path(of pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    public static func bootSessionUUID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// The record this process should write to its pid file.
    public static func currentRecord() -> PidRecord? {
        let pid = getpid()
        guard let start = startTime(of: pid), let boot = bootSessionUUID() else { return nil }
        return PidRecord(pid: pid, startTime: start, bootSession: boot)
    }
}
