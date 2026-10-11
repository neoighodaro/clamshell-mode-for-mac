import ClamSignal
import Foundation

/// Connects the C signal handlers to the app: a termination signal becomes a clean quit.
final class SignalBridge {
    private var source: DispatchSourceRead?

    /// Installs the handlers. `onTermination` runs on the main queue for SIGTERM, SIGINT, SIGHUP and SIGQUIT.
    func install(onTermination: @escaping () -> Void) -> Bool {
        guard clam_signal_install() == 0 else { return false }
        let fd = clam_signal_termination_fd()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 16)
            _ = read(fd, &buffer, buffer.count)
            onTermination()
        }
        source.resume()
        self.source = source
        return true
    }

    /// The clean quit finished; cancel the handler's 5 second alarm.
    func terminationFinished() {
        clam_signal_termination_done()
    }
}
