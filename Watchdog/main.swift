import ClamCore
import Foundation

// ClamWatchdog: waits for Clam to exit. After an unclean exit it clears the
// lid-sleep flag, then relaunches the app unless it is crash-looping.
// Exit status 0 always: launchd restarts this agent only if it crashes.

guard let directory = try? ClamPaths.directory() else {
    // No diagnostics log and no pid file to read, so a live Clam cannot be ruled out. Clearing
    // the flag could re-enable sleep under an armed session, so only record the failure.
    NSLog("ClamWatchdog: cannot open the Application Support folder; leaving the flag alone")
    exit(0)
}
let log = DiagnosticLog(url: ClamPaths.log(in: directory))
let pidFile = PidFile(url: ClamPaths.pidFile(in: directory))
var guardian = CrashLoopGuard(url: ClamPaths.relaunchHistory(in: directory))

func say(_ message: String) {
    log.log("watchdog: \(message)")
}

/// Clears the flag, up to 3 tries 200 ms apart. Returns whether it succeeded.
func clearFlag() -> Bool {
    for attempt in 0..<3 {
        if attempt > 0 { usleep(200_000) }
        if SleepFlag.clearOnce() { return true }
    }
    return false
}

func matches(_ record: PidRecord) -> Bool {
    WatchdogLogic.matchesClam(record: record,
                              alive: ProcessInspector.isAlive(record.pid),
                              startTime: ProcessInspector.startTime(of: record.pid),
                              path: ProcessInspector.path(of: record.pid))
}

/// A live process that fails the match may only be briefly uninspectable. Retry up to
/// 3 times, 200 ms apart, before treating it as not Clam: a live Clam must not get its flag cleared.
func isClam(_ record: PidRecord) -> Bool {
    if matches(record) { return true }
    for _ in 0..<3 {
        guard ProcessInspector.isAlive(record.pid) else { return false }
        usleep(200_000)
        if matches(record) { return true }
    }
    return false
}

/// Blocks until `pid` exits. The watchdog is not its parent, so it uses a
/// process dispatch source, and re-checks liveness in case the exit was missed.
func waitForExit(of pid: pid_t) {
    let exited = DispatchSemaphore(value: 0)
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
    source.setEventHandler { exited.signal() }
    source.resume()
    while ProcessInspector.isAlive(pid) {
        if exited.wait(timeout: .now() + 5) == .success { break }
    }
    source.cancel()
}

/// `<app>/Contents/MacOS/ClamWatchdog` -> `<app>`.
func appURL() -> URL {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return executable.resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

func relaunchApp() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", appURL().path]
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

func waitForNewPidFile(seconds: Int) -> Bool {
    for _ in 0..<(seconds * 2) {
        if let record = pidFile.read(), isClam(record) { return true }
        usleep(500_000)
    }
    return false
}

/// A new instance may have replaced the one that died: the user relaunched it, or the login
/// item started it. It cleared the flag at launch and may be armed again by now, so neither
/// its pid file nor the flag is ours to touch.
func liveInstanceOwnsPidFile() -> Bool {
    guard let record = pidFile.read(), isClam(record) else { return false }
    say("a live instance (pid \(record.pid)) owns the pid file; monitoring it")
    return true
}

/// Returns when an app instance is running and should be monitored; exits the process otherwise.
/// The pid file is read again before every removal: an instance can start at any point here.
func recover() {
    if liveInstanceOwnsPidFile() { return }
    for action in WatchdogLogic.afterUncleanExit(guardStandsDown: guardian.shouldStandDown(at: Date())) {
        switch action {
        case .clearFlag:
            say("unclean exit; clearing the flag: \(clearFlag() ? "ok" : "FAILED after 3 tries")")
        case .standDown:
            if liveInstanceOwnsPidFile() { return }
            say("three relaunches in five minutes; standing down")
            pidFile.remove()
            exit(0)
        case .relaunch:
            if liveInstanceOwnsPidFile() { return }
            guardian.recordRelaunch(at: Date())
            pidFile.remove()
            guard relaunchApp(), waitForNewPidFile(seconds: 30) else {
                say("relaunched app wrote no pid file within 30s; clearing the flag again: \(clearFlag() ? "ok" : "FAILED after 3 tries")")
                exit(0)
            }
            say("relaunched")
        }
    }
}

while true {
    let start = WatchdogLogic.onStart(pidFileExists: pidFile.exists, record: pidFile.read(),
                                      currentBootSession: ProcessInspector.bootSessionUUID(),
                                      isClam: isClam)
    switch start {
    case .exitClean:
        exit(0)
    case .removeStaleAndExit:
        if liveInstanceOwnsPidFile() { continue }
        say("pid file predates this boot; removing")
        pidFile.remove()
        exit(0)
    case .monitor(let pid):
        say("monitoring pid \(pid)")
        waitForExit(of: pid)
        if WatchdogLogic.onAppExit(pidFileExists: pidFile.exists) == .clean {
            say("clean exit")
            exit(0)
        }
        recover()
    case .unclean:
        recover()
    }
}
