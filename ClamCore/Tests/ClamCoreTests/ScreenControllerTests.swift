import Foundation
import Testing
@testable import ClamCore

private final class ScreenHarness {
    let brightness = FakeBrightness()
    let locker = FakeLocker()
    let sleeper = FakeSleeper()
    let assertions = FakeAssertions()
    let scheduler = ManualScheduler()
    let store: RestoreRecordStore
    var notices: [ScreenNotice] = []
    var lockVerified = true
    lazy var screen: ScreenController = {
        let s = ScreenController(brightness: brightness, locker: locker, sleeper: sleeper,
                                 store: store, assertions: assertions, scheduler: scheduler,
                                 lockVerified: { [unowned self] in self.lockVerified })
        s.onNotice = { [unowned self] in self.notices.append($0) }
        return s
    }()

    init(url: URL = temporaryFile("restore.json")) {
        store = RestoreRecordStore(url: url)
    }
}

@Test func recordRoundTrips() throws {
    let store = RestoreRecordStore(url: temporaryFile("restore.json"))
    #expect(!store.exists)
    #expect(store.load() == nil)
    try store.save(RestoreRecord(brightness: 0.42, lockOwed: true))
    #expect(store.exists)
    #expect(store.load() == RestoreRecord(brightness: 0.42, lockOwed: true))
    store.delete()
    #expect(!store.exists)
}

// A corrupt record must still lead to a visible, locked screen.
@Test func corruptRecordLoadsAsASafeDefault() throws {
    let url = temporaryFile("restore.json")
    try Data("{ not json".utf8).write(to: url)
    let store = RestoreRecordStore(url: url)
    #expect(store.load() == RestoreRecord(brightness: RestoreRecordStore.fallbackBrightness, lockOwed: true))
}

// A record that would restore to a black or out-of-range level restores to a visible one.
@Test(arguments: [Float(0), 0.04, -1, 1.5]) func recordWithAnUnusableBrightnessLoadsTheFallback(_ saved: Float) throws {
    let url = temporaryFile("restore.json")
    try Data(#"{"brightness":\#(saved),"lockOwed":false}"#.utf8).write(to: url)
    let store = RestoreRecordStore(url: url)
    #expect(store.load() == RestoreRecord(brightness: RestoreRecordStore.fallbackBrightness, lockOwed: false))
}

@Test func usableBrightnessIsKeptAndUnusableBrightnessIsReplaced() {
    let fallback = RestoreRecordStore.fallbackBrightness
    #expect(RestoreRecordStore.usableBrightness(0.06) == 0.06)
    #expect(RestoreRecordStore.usableBrightness(1) == 1)
    #expect(RestoreRecordStore.usableBrightness(0) == fallback)
    #expect(RestoreRecordStore.usableBrightness(0.04) == fallback)
    #expect(RestoreRecordStore.usableBrightness(1.01) == fallback)
    #expect(RestoreRecordStore.usableBrightness(.nan) == fallback)
    #expect(RestoreRecordStore.usableBrightness(nil) == fallback)
}

@Test func displayOffRunsPmsetOnce() {
    let h = ScreenHarness()
    h.screen.lidClosed(mode: .displayOff)
    #expect(h.sleeper.calls == 1)
    #expect(h.notices.isEmpty)
    #expect(!h.store.exists)
}

@Test func displayOffRetriesOnceThenWarns() {
    let h = ScreenHarness()
    h.sleeper.results = [false, true]
    h.screen.lidClosed(mode: .displayOff)
    #expect(h.sleeper.calls == 2)
    #expect(h.notices.isEmpty)

    let failing = ScreenHarness()
    failing.sleeper.results = [false, false]
    failing.screen.lidClosed(mode: .displayOff)
    #expect(failing.sleeper.calls == 2)
    #expect(failing.notices == [.displayMayStayLit])
}

@Test func agentsScreenPersistsThenDarkens() {
    let h = ScreenHarness()
    h.brightness.value = 0.7
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(h.store.load() == RestoreRecord(brightness: 0.7, lockOwed: true))
    #expect(h.brightness.value == 0)
    #expect(h.assertions.displayAwake)
    #expect(h.sleeper.calls == 0)
    #expect(h.notices.isEmpty)
}

@Test func agentsScreenRefusesToDarkenWhenTheRecordCannotBeWritten() {
    // A path inside a directory that does not exist cannot be written.
    let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/restore.json")
    let h = ScreenHarness(url: url)
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(h.brightness.sets.isEmpty)
    #expect(h.notices == [.couldNotPersist])
    // Not darkened, and no lock is owed, so the screen must not stay lit: display off instead.
    #expect(h.sleeper.calls == 1)
    #expect(!h.assertions.displayAwake)
}

@Test func agentsScreenIsDisplayOffUntilTheLockIsVerified() {
    let h = ScreenHarness()
    h.lockVerified = false
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(h.sleeper.calls == 1)
    #expect(h.brightness.sets.isEmpty)
    #expect(!h.store.exists)
    #expect(!h.assertions.displayAwake)
    #expect(h.notices == [.lockNotVerified])
}

// With the lid shutting, the built-in display can read as zero or not at all.
@Test(arguments: [Float?.some(0), 0.04, nil]) func aDarkOrMissingBrightnessReadSavesAVisibleLevel(_ read: Float?) {
    let h = ScreenHarness()
    h.brightness.value = read
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(h.store.load() == RestoreRecord(brightness: RestoreRecordStore.fallbackBrightness, lockOwed: true))
    #expect(h.brightness.sets == [0])
    #expect(h.sleeper.calls == 0)

    h.locker.locksOnRequest = true
    h.screen.processPendingRestore(lidOpen: true)
    #expect(h.brightness.value == RestoreRecordStore.fallbackBrightness)
    #expect(!h.store.exists)
}

@Test func agentsScreenFallsBackWhenBrightnessIsUnavailable() {
    let h = ScreenHarness()
    h.brightness.isAvailable = false
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(h.sleeper.calls == 1)
    #expect(h.notices == [.agentsScreenUnavailable])
    #expect(!h.store.exists)
}

@Test func darkenThatDoesNotTakeIsReported() {
    let h = ScreenHarness()
    h.brightness.setSucceeds = false
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(h.notices == [.darkenFailed])
    #expect(h.store.exists)
}

@Test func restoreLocksFirstThenRestoresOnceLocked() {
    let h = ScreenHarness()
    h.screen.lidClosed(mode: .agentsScreen)
    h.screen.processPendingRestore(lidOpen: true)
    #expect(h.locker.requests == 1)
    #expect(h.brightness.value == 0)
    #expect(!h.assertions.displayAwake)

    h.scheduler.advance(by: 0.55)
    #expect(h.brightness.value == 0)

    h.locker.isLocked = true
    h.scheduler.advance(by: 0.25)
    #expect(h.brightness.value == 0.8)
    #expect(!h.store.exists)
    #expect(h.notices.isEmpty)
}

@Test func restoreFailsSafeAfterThreeSeconds() {
    let h = ScreenHarness()
    h.screen.lidClosed(mode: .agentsScreen)
    h.screen.processPendingRestore(lidOpen: true)
    h.scheduler.advance(by: 2.5)
    #expect(h.brightness.value == 0)
    h.scheduler.advance(by: 1)
    #expect(h.brightness.value == 0.8)
    #expect(!h.store.exists)
    #expect(h.notices == [.lockUnconfirmed])
}

@Test func restoreDoesNothingWithTheLidShutOrWithoutARecord() {
    let h = ScreenHarness()
    h.screen.processPendingRestore(lidOpen: true)
    #expect(h.locker.requests == 0)

    h.screen.lidClosed(mode: .agentsScreen)
    h.screen.processPendingRestore(lidOpen: false)
    #expect(h.locker.requests == 0)
    #expect(h.store.exists)
}

@Test func aSecondRestoreCallWhileWaitingDoesNotLockTwice() {
    let h = ScreenHarness()
    h.screen.lidClosed(mode: .agentsScreen)
    h.screen.processPendingRestore(lidOpen: true)
    h.screen.processPendingRestore(lidOpen: true)
    #expect(h.locker.requests == 1)
}

// Lid re-closed while the lock is still being confirmed.
@Test func reclosingDuringTheLockWaitKeepsTheRecordAndStaysDark() {
    let h = ScreenHarness()
    h.brightness.value = 0.7
    h.screen.lidClosed(mode: .agentsScreen)
    h.screen.processPendingRestore(lidOpen: true)
    h.scheduler.advance(by: 1)
    h.screen.lidClosed(mode: .agentsScreen)
    h.scheduler.advance(by: 10)
    #expect(h.brightness.value == 0)
    // The original brightness survives, not the zero read at the second close.
    #expect(h.store.load() == RestoreRecord(brightness: 0.7, lockOwed: true))
    #expect(h.notices.isEmpty)
}

// A screen left at zero brightness looks like a dead Mac, so a failed restore retries by itself.
@Test func failedBrightnessRestoreRetriesEverySecond() {
    let h = ScreenHarness()
    h.screen.lidClosed(mode: .agentsScreen)
    h.locker.locksOnRequest = true
    h.brightness.setSucceeds = false
    h.screen.processPendingRestore(lidOpen: true)
    h.scheduler.advance(by: 2.5)
    #expect(h.store.exists)

    h.brightness.setSucceeds = true
    h.scheduler.advance(by: 1)
    #expect(h.brightness.value == 0.8)
    #expect(!h.store.exists)
    #expect(h.notices.isEmpty)
}

@Test func brightnessRestoreGivesUpWithANoticeAndKeepsTheRecord() {
    let h = ScreenHarness()
    var done = 0
    h.screen.lidClosed(mode: .agentsScreen)
    h.locker.locksOnRequest = true
    h.brightness.setSucceeds = false
    h.screen.processPendingRestore(lidOpen: true) { done += 1 }
    h.scheduler.advance(by: 9.5)
    #expect(done == 0)
    #expect(h.notices.isEmpty)
    h.scheduler.advance(by: 1)
    #expect(done == 1)
    #expect(h.notices == [.restoreFailed])
    #expect(h.store.exists)

    // The next lid open, wake or launch tries again from the record.
    h.brightness.setSucceeds = true
    h.screen.processPendingRestore(lidOpen: true)
    #expect(h.brightness.value == 0.8)
    #expect(!h.store.exists)
}

// Quit waits on this completion; a lid close during the wait must not strand it.
@Test func reclosingRunsPendingCompletions() {
    let h = ScreenHarness()
    var done = 0
    h.screen.lidClosed(mode: .agentsScreen)
    h.screen.processPendingRestore(lidOpen: true) { done += 1 }
    #expect(done == 0)
    h.screen.lidClosed(mode: .agentsScreen)
    #expect(done == 1)
    #expect(h.store.exists)
}

@Test func completionRunsAfterRestoreOrImmediatelyWhenNothingIsPending() {
    let h = ScreenHarness()
    var done = 0
    h.screen.processPendingRestore(lidOpen: true) { done += 1 }
    #expect(done == 1)

    h.screen.lidClosed(mode: .agentsScreen)
    h.locker.locksOnRequest = true
    h.screen.processPendingRestore(lidOpen: true) { done += 1 }
    #expect(done == 2)
    #expect(!h.store.exists)
}
