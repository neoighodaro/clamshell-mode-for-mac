import Testing
@testable import ClamCore

@Test func rivalAlreadyRunningAtTheFirstReadingIsNotALaunch() {
    var tracker = RivalTracker()
    #expect(tracker.update(running: true) == false)
    #expect(tracker.update(running: true) == false)
}

@Test func rivalStartingIsReportedOnce() {
    var tracker = RivalTracker()
    #expect(tracker.update(running: false) == false)
    #expect(tracker.update(running: true) == true)
    // A second source noticing the same launch must not report it again.
    #expect(tracker.update(running: true) == false)
}

@Test func rivalQuittingIsNotALaunchButTheNextStartIs() {
    var tracker = RivalTracker()
    _ = tracker.update(running: false)
    _ = tracker.update(running: true)
    #expect(tracker.update(running: false) == false)
    #expect(tracker.update(running: true) == true)
}

// The path the 30 second refresh takes when no launch notification arrives.
@Test func aLaunchSeenOnlyByARefreshDisarmsAnArmedSession() {
    let h = Harness()
    var tracker = RivalTracker()
    func refresh() {
        if tracker.update(running: h.env.rivalRunning) { h.send(.rivalLaunched) }
    }
    refresh()
    h.send(.arm)
    h.env.rivalRunning = true
    refresh()
    refresh()
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
    #expect(h.notices == [.rivalLaunched])
}
