import Foundation
import ServiceManagement

enum WatchdogHealth: Equatable {
    case running
    /// Registered, but the user has not allowed it in Login Items.
    case notApproved
    case unavailable(String)
}

/// Registers the watchdog LaunchAgent and makes sure it is running.
final class WatchdogManager {
    static let label = "co.creativitykills.clam.watchdog"

    private let queue = DispatchQueue(label: "co.creativitykills.clam.watchdog-check", qos: .utility)
    private let service = SMAppService.agent(plistName: "\(WatchdogManager.label).plist")
    private(set) var health: WatchdogHealth = .unavailable("not checked yet")

    var statusText: String {
        switch health {
        case .running: return "Relaunch protection is on."
        case .notApproved: return "Relaunch protection is off. Allow Clam in System Settings > General > Login Items."
        case .unavailable(let why): return "Relaunch protection is unavailable (\(why))."
        }
    }

    /// Registers if needed, kickstarts, and confirms. Runs off the main thread;
    /// `completion` is called on the main queue.
    /// Checks are serialised, so a launch check and a first-arm check never overlap.
    /// `pidFilePresent` is read on the check queue: without a pid file the watchdog exits 0
    /// by design, so not running is not a fault to repair and the answer is not-protected.
    func ensureRunning(pidFilePresent: @escaping () -> Bool, completion: @escaping (WatchdogHealth) -> Void) {
        queue.async { [self] in
            let result = check(pidFilePresent: pidFilePresent)
            DispatchQueue.main.async {
                self.health = result
                completion(result)
            }
        }
    }

    private func check(pidFilePresent: () -> Bool) -> WatchdogHealth {
        if service.status != .enabled {
            do {
                try service.register()
            } catch {
                if service.status == .requiresApproval { return .notApproved }
                return .unavailable(error.localizedDescription)
            }
        }
        if service.status == .requiresApproval { return .notApproved }
        guard service.status == .enabled else { return .unavailable("not enabled") }

        kickstart()
        if waitUntilRunning() { return pidFilePresent() ? .running : .unavailable("no pid file") }
        if !pidFilePresent() { return .unavailable("no pid file") }

        // The registration may point at an old copy of the app. Re-register against this bundle.
        try? service.unregister()
        usleep(500_000)
        do { try service.register() } catch { return .unavailable(error.localizedDescription) }
        kickstart()
        guard waitUntilRunning() else { return .unavailable("did not start") }
        return pidFilePresent() ? .running : .unavailable("no pid file")
    }

    private var serviceTarget: String { "gui/\(getuid())/\(Self.label)" }

    private func kickstart() {
        _ = launchctl(["kickstart", serviceTarget])
    }

    private func waitUntilRunning() -> Bool {
        for _ in 0..<10 {
            if launchctl(["print", serviceTarget])?.contains("state = running") == true { return true }
            usleep(200_000)
        }
        return false
    }

    private func launchctl(_ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
