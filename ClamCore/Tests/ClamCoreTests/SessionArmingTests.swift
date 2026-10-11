import Testing
@testable import ClamCore

@Test func toggleArmsAndDisarms() {
    let h = Harness()
    h.send(.toggle)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.flag.isSet)
    #expect(h.assertions.keepAwake)

    h.send(.toggle)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
    #expect(!h.assertions.keepAwake)
    #expect(h.notices.isEmpty)
}

@Test func failedArmStaysDisarmedAndTellsTheUser() {
    let h = Harness()
    h.flag.setSucceeds = false
    h.send(.arm)
    #expect(h.controller.state == .disarmed)
    #expect(!h.assertions.keepAwake)
    #expect(h.notices == [.armFailed])
}

@Test func armingIsBlockedBySafety() {
    let h = Harness()
    h.env.thermal = .serious
    h.send(.toggle)
    #expect(h.controller.state == .disarmed)
    #expect(h.flag.calls.isEmpty)
    #expect(h.notices == [.armBlocked(.thermal)])
}

@Test func armingWithAnExternalDisplayGoesToPaused() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm)
    #expect(h.controller.state == .paused)
    #expect(h.flag.calls.isEmpty)
    #expect(h.notices == [.pausedForExternalDisplay])
}

@Test func armingWithTheLidShutGoesStraightToClosed() {
    let h = Harness()
    h.env.lidClosed = true
    h.settings.screenMode = .agentsScreen
    h.send(.arm)
    #expect(h.controller.state == .closed(.persistent))
    #expect(h.screen.closedModes == [.agentsScreen])
}

@Test func tiltArmsForOneClose() {
    let h = Harness()
    h.send(.tiltArm)
    #expect(h.controller.state == .armed(.oneClose))
    h.send(.tiltCancel)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
}

@Test func tiltIsIgnoredUnlessDisarmedWithNoExternalDisplay() {
    let armed = Harness()
    armed.send(.arm, .tiltArm)
    #expect(armed.controller.state == .armed(.persistent))
    armed.send(.tiltCancel)
    #expect(armed.controller.state == .armed(.persistent))

    let docked = Harness()
    docked.env.externalDisplay = true
    docked.send(.tiltArm)
    #expect(docked.controller.state == .disarmed)
    #expect(docked.notices.isEmpty)
}

@Test func toggleDisarmsAOneCloseArm() {
    let h = Harness()
    h.send(.tiltArm, .toggle)
    #expect(h.controller.state == .disarmed)
}

@Test func explicitArmUpgradesOneCloseToPersistent() {
    let h = Harness()
    h.send(.tiltArm, .arm)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.flag.calls == [true])
}

@Test func toggleCancelsAPausedArm() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm, .toggle)
    #expect(h.controller.state == .disarmed)
}

@Test func failedClearRetriesEveryFiveSecondsUntilItWorks() {
    let h = Harness()
    h.send(.arm)
    h.flag.clearSucceeds = false
    h.send(.disarm)
    #expect(h.controller.state == .disarmed)
    #expect(h.controller.clearPending)
    #expect(h.notices == [.clearFailed])

    h.scheduler.advance(by: 5)
    #expect(h.controller.clearPending)
    #expect(h.notices == [.clearFailed])

    h.flag.clearSucceeds = true
    h.scheduler.advance(by: 5)
    #expect(!h.controller.clearPending)
    #expect(!h.flag.isSet)
    #expect(h.notices == [.clearFailed, .clearRecovered])
}

@Test func manualRetryClearsImmediately() {
    let h = Harness()
    h.send(.arm)
    h.flag.clearSucceeds = false
    h.send(.disarm)
    h.flag.clearSucceeds = true
    h.controller.retryClear()
    #expect(!h.controller.clearPending)
    #expect(!h.flag.isSet)
}

// Arming again while a failed clear is retrying.
@Test func rearmingCancelsThePendingClearRetry() {
    let h = Harness()
    h.send(.arm)
    h.flag.clearSucceeds = false
    h.send(.disarm)
    h.flag.clearSucceeds = true
    h.send(.arm)
    #expect(!h.controller.clearPending)
    h.scheduler.advance(by: 60)
    #expect(h.flag.isSet)
    #expect(h.controller.state == .armed(.persistent))
}

@Test func shutdownClearsAndReportsSuccess() {
    let h = Harness()
    h.send(.arm)
    #expect(h.controller.shutdown())
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)

    let failing = Harness()
    failing.send(.arm)
    failing.flag.clearSucceeds = false
    #expect(!failing.controller.shutdown())
}

// A queued Shortcuts action or hotkey must not re-arm after the final clear.
@Test func eventsAfterShutdownAreIgnored() {
    let h = Harness()
    h.send(.arm)
    _ = h.controller.shutdown()
    h.send(.toggle, .arm)
    h.controller.retryClear()
    #expect(h.controller.state == .disarmed)
    #expect(h.flag.calls == [true, false])
}

@Test func stateChangesAreReported() {
    let h = Harness()
    h.send(.arm, .disarm)
    #expect(h.transitions == [.armed(.persistent), .disarmed])
}

@Test func failedLaunchClearNotifiesAndRetriesUntilItSucceeds() {
    let h = Harness()
    h.flag.clearSucceeds = false
    h.controller.clearAtLaunch()
    #expect(h.controller.clearPending)
    #expect(h.notices == [.clearFailed])
    h.scheduler.advance(by: 5)
    #expect(h.controller.clearPending)
    h.flag.clearSucceeds = true
    h.scheduler.advance(by: 5)
    #expect(!h.controller.clearPending)
    #expect(h.notices == [.clearFailed, .clearRecovered])
}

@Test func launchClearIsSkippedWhileTheRivalRuns() {
    let h = Harness()
    h.env.rivalRunning = true
    h.controller.clearAtLaunch()
    #expect(h.flag.calls.isEmpty)
    #expect(!h.controller.clearPending)
}

@Test func launchClearRetryWaitsOutTheRival() {
    let h = Harness()
    h.flag.clearSucceeds = false
    h.controller.clearAtLaunch()
    let before = h.flag.calls.count
    h.env.rivalRunning = true
    h.scheduler.advance(by: 20)
    #expect(h.flag.calls.count == before)
    #expect(h.controller.clearPending)
    h.env.rivalRunning = false
    h.flag.clearSucceeds = true
    h.scheduler.advance(by: 20)
    #expect(!h.controller.clearPending)
}
