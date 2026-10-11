import Foundation

/// Turns the display off with `pmset displaysleepnow`.
public final class PmsetDisplaySleeper: DisplaySleeping {
    private let executable: String
    private let arguments: [String]
    private let timeout: TimeInterval

    public convenience init() {
        self.init(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"], timeout: 2)
    }

    /// Test seam: runs another command in place of pmset.
    init(executable: String, arguments: [String], timeout: TimeInterval) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }

    /// Waits for the command without running the caller's run loop, so nothing else on the
    /// main thread runs in the middle of a lid transition, and gives up after `timeout`.
    public func sleepDisplay() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return false
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }
}
