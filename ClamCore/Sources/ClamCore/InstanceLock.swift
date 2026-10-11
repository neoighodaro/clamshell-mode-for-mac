import Darwin
import Foundation

/// An exclusive `flock` held for the life of the process.
/// Opened `O_CLOEXEC` so child processes (pmset, osascript, launchctl) cannot keep it alive.
public final class InstanceLock {
    private let descriptor: Int32

    public init?(url: URL) {
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
