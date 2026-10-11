import Foundation
import Testing
@testable import ClamCore

@Test func pidFileRoundTripsAndRemoves() throws {
    let file = PidFile(url: temporaryFile("clam.pid"))
    #expect(!file.exists)
    #expect(file.read() == nil)
    let record = PidRecord(pid: 4242, startTime: 1_760_000_000.5, bootSession: "ABC")
    try file.write(record)
    #expect(file.exists)
    #expect(file.read() == record)
    file.remove()
    #expect(!file.exists)
}

// A truncated pid file exists but cannot be read.
@Test func corruptPidFileExistsButReadsAsNil() throws {
    let url = temporaryFile("clam.pid")
    try Data("{\"pid\": 12".utf8).write(to: url)
    let file = PidFile(url: url)
    #expect(file.exists)
    #expect(file.read() == nil)
}

@Test func processInspectorDescribesThisProcess() {
    let me = getpid()
    #expect(ProcessInspector.isAlive(me))
    #expect(ProcessInspector.startTime(of: me) != nil)
    #expect(ProcessInspector.path(of: me)?.isEmpty == false)
    #expect(ProcessInspector.bootSessionUUID()?.isEmpty == false)
    let record = ProcessInspector.currentRecord()
    #expect(record?.pid == me)
}

@Test func processInspectorReportsADeadPid() {
    // Pid 0x7FFFFFF0 is far above the macOS pid limit of 99998.
    #expect(!ProcessInspector.isAlive(0x7FFF_FFF0))
    #expect(ProcessInspector.startTime(of: 0x7FFF_FFF0) == nil)
}

@Test func processInspectorRejectsNonPositivePids() {
    // kill(0, _) and kill(-1, _) would signal a process group or every process.
    #expect(!ProcessInspector.isAlive(0))
    #expect(!ProcessInspector.isAlive(-1))
}

@Test func crashLoopGuardStandsDownAfterThreeRelaunchesInFiveMinutes() {
    let url = temporaryFile("relaunches.json")
    var guardian = CrashLoopGuard(url: url)
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    #expect(!guardian.shouldStandDown(at: t0))
    guardian.recordRelaunch(at: t0)
    guardian.recordRelaunch(at: t0.addingTimeInterval(60))
    #expect(!guardian.shouldStandDown(at: t0.addingTimeInterval(61)))
    guardian.recordRelaunch(at: t0.addingTimeInterval(120))
    #expect(guardian.shouldStandDown(at: t0.addingTimeInterval(121)))
    // The first relaunch ages out after five minutes.
    #expect(!guardian.shouldStandDown(at: t0.addingTimeInterval(301)))
}

@Test func crashLoopGuardPersistsAcrossInstances() {
    let url = temporaryFile("relaunches.json")
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var first = CrashLoopGuard(url: url)
    first.recordRelaunch(at: t0)
    first.recordRelaunch(at: t0)
    first.recordRelaunch(at: t0)
    let second = CrashLoopGuard(url: url)
    #expect(second.shouldStandDown(at: t0.addingTimeInterval(1)))
}

// Corrupt relaunch history.
@Test func crashLoopGuardTreatsCorruptHistoryAsEmpty() throws {
    let url = temporaryFile("relaunches.json")
    try Data("garbage".utf8).write(to: url)
    let guardian = CrashLoopGuard(url: url)
    #expect(!guardian.shouldStandDown(at: Date()))
}

@Test func instanceLockIsExclusive() {
    let url = temporaryFile("clam.lock")
    let first = InstanceLock(url: url)
    #expect(first != nil)
    #expect(InstanceLock(url: url) == nil)
}

@Test func instanceLockIsReleasedOnDeinit() {
    let url = temporaryFile("clam.lock")
    var first = InstanceLock(url: url)
    #expect(first != nil)
    first = nil
    #expect(InstanceLock(url: url) != nil)
}

@Test func diagnosticLogAppendsAndTruncatesWhenTooLarge() throws {
    let url = temporaryFile("diagnostics.log")
    let log = DiagnosticLog(url: url, maxBytes: 200)
    log.log("first")
    log.log("second")
    var text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("first"))
    #expect(text.contains("second"))

    for i in 0..<20 { log.log("line \(i) padding padding padding") }
    text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.utf8.count <= 400)
    #expect(text.contains("line 19"))
    #expect(!text.contains("first"))
}

@Test func pathsLiveInOneDirectory() {
    let dir = URL(fileURLWithPath: "/tmp/x")
    #expect(ClamPaths.pidFile(in: dir).lastPathComponent == "clam.pid")
    #expect(ClamPaths.lockFile(in: dir).lastPathComponent == "clam.lock")
    #expect(ClamPaths.restoreRecord(in: dir).lastPathComponent == "display-brightness-recovery.json")
    #expect(ClamPaths.relaunchHistory(in: dir).lastPathComponent == "relaunches.json")
    #expect(ClamPaths.log(in: dir).lastPathComponent == "diagnostics.log")
}
