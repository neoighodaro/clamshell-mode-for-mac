import Foundation

public enum ClamPaths {
    /// `~/Library/Application Support/Clam`, created if missing.
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Clam", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func pidFile(in dir: URL) -> URL { dir.appendingPathComponent("clam.pid") }
    public static func lockFile(in dir: URL) -> URL { dir.appendingPathComponent("clam.lock") }
    public static func restoreRecord(in dir: URL) -> URL {
        dir.appendingPathComponent("display-brightness-recovery.json")
    }
    public static func relaunchHistory(in dir: URL) -> URL { dir.appendingPathComponent("relaunches.json") }
    public static func log(in dir: URL) -> URL { dir.appendingPathComponent("diagnostics.log") }
}
