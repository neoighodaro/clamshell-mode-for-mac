import Testing
@testable import ClamCore

private let record = PidRecord(pid: 500, startTime: 1000, bootSession: "BOOT-A")

@Test func noPidFileMeansNothingToWatch() {
    let d = WatchdogLogic.onStart(pidFileExists: false, record: nil, currentBootSession: "BOOT-A") { _ in true }
    #expect(d == .exitClean)
}

// An unreadable pid file means the app died mid-write or the file is damaged.
@Test func unreadablePidFileIsAnUncleanExit() {
    let d = WatchdogLogic.onStart(pidFileExists: true, record: nil, currentBootSession: "BOOT-A") { _ in true }
    #expect(d == .unclean)
}

@Test func pidFileFromAnEarlierBootIsStale() {
    let d = WatchdogLogic.onStart(pidFileExists: true, record: record, currentBootSession: "BOOT-B") { _ in true }
    #expect(d == .removeStaleAndExit)
}

@Test func unknownBootSessionIsNotTreatedAsStale() {
    let d = WatchdogLogic.onStart(pidFileExists: true, record: record, currentBootSession: nil) { _ in true }
    #expect(d == .monitor(pid: 500))
}

@Test func liveClamIsMonitored() {
    let d = WatchdogLogic.onStart(pidFileExists: true, record: record, currentBootSession: "BOOT-A") { _ in true }
    #expect(d == .monitor(pid: 500))
}

@Test func deadOrReusedPidIsAnUncleanExit() {
    let d = WatchdogLogic.onStart(pidFileExists: true, record: record, currentBootSession: "BOOT-A") { _ in false }
    #expect(d == .unclean)
}

@Test func exitWithoutPidFileIsClean() {
    #expect(WatchdogLogic.onAppExit(pidFileExists: false) == .clean)
    #expect(WatchdogLogic.onAppExit(pidFileExists: true) == .unclean)
}

// Every unclean path clears the flag before anything else.
@Test func recoveryClearsTheFlagFirstThenRelaunchesOrStandsDown() {
    #expect(WatchdogLogic.afterUncleanExit(guardStandsDown: false) == [.clearFlag, .relaunch])
    #expect(WatchdogLogic.afterUncleanExit(guardStandsDown: true) == [.clearFlag, .standDown])
}

@Test func matchesClamRequiresLivenessStartTimeAndPath() {
    let path = "/Applications/Clam.app/Contents/MacOS/Clam"
    #expect(WatchdogLogic.matchesClam(record: record, alive: true, startTime: 1000.4, path: path))
    #expect(!WatchdogLogic.matchesClam(record: record, alive: false, startTime: 1000, path: path))
    // Same pid, different start time: the pid was reused.
    #expect(!WatchdogLogic.matchesClam(record: record, alive: true, startTime: 2000, path: path))
    #expect(!WatchdogLogic.matchesClam(record: record, alive: true, startTime: nil, path: path))
    #expect(!WatchdogLogic.matchesClam(record: record, alive: true, startTime: 1000, path: "/usr/bin/yes"))
    #expect(!WatchdogLogic.matchesClam(record: record, alive: true, startTime: 1000, path: nil))
    // The watchdog itself must not match.
    #expect(!WatchdogLogic.matchesClam(record: record, alive: true, startTime: 1000,
                                       path: "/Applications/Clam.app/Contents/MacOS/ClamWatchdog"))
}
