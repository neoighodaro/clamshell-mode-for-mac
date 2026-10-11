import Testing
@testable import ClamCore

@Test func lidCloseWhileArmedAppliesTheScreenMode() {
    let h = Harness()
    h.settings.screenMode = .displayOff
    h.send(.arm, .lidClosed)
    #expect(h.controller.state == .closed(.persistent))
    #expect(h.screen.closedModes == [.displayOff])
    #expect(h.assertions.transitionGuard)
}

@Test func lidOpenAfterAPersistentCloseStaysArmed() {
    let h = Harness()
    h.send(.arm, .lidClosed, .lidOpened)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.flag.isSet)
    #expect(h.screen.restoreCalls == [true])
}

@Test func lidOpenAfterAOneCloseDisarms() {
    let h = Harness()
    h.send(.tiltArm, .lidClosed)
    #expect(h.controller.state == .closed(.oneClose))
    h.send(.lidOpened)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
    #expect(!h.assertions.keepAwake)
    #expect(h.screen.restoreCalls == [true])
}

@Test func explicitArmWhileClosedUpgradesOneClose() {
    let h = Harness()
    h.send(.tiltArm, .lidClosed, .arm, .lidOpened)
    #expect(h.controller.state == .armed(.persistent))
}

@Test func transitionGuardIsReleasedAfterTenSecondsAndTheFlagReapplied() {
    let h = Harness()
    h.send(.arm, .lidClosed)
    let callsBefore = h.flag.calls.count
    h.scheduler.advance(by: 9)
    #expect(h.assertions.transitionGuard)
    h.scheduler.advance(by: 2)
    #expect(!h.assertions.transitionGuard)
    #expect(h.flag.calls.count == callsBefore + 1)
    #expect(h.flag.calls.last == true)
}

@Test func reapplyTriggerSetsTheFlagAgainWhileArmedOrClosed() {
    let h = Harness()
    h.send(.arm, .reapplyTrigger)
    #expect(h.flag.calls == [true, true])
    h.send(.lidClosed, .reapplyTrigger)
    #expect(h.flag.calls == [true, true, true])
}

@Test func reapplyTriggerDoesNothingWhileDisarmed() {
    let h = Harness()
    h.send(.reapplyTrigger)
    #expect(h.flag.calls.isEmpty)
}

@Test func failedReapplyForcesDisarmed() {
    let h = Harness()
    h.send(.arm)
    h.flag.setSucceeds = false
    h.send(.reapplyTrigger)
    #expect(h.controller.state == .disarmed)
    #expect(!h.assertions.keepAwake)
    #expect(h.notices == [.reapplyFailed])
    #expect(h.flag.calls.last == false)
}

@Test func lidOpenAlwaysProcessesAPendingRestore() {
    let h = Harness()
    h.send(.lidOpened)
    #expect(h.controller.state == .disarmed)
    #expect(h.screen.restoreCalls == [true])
}

// Duplicate and out-of-order lid events.
@Test func duplicateLidCloseAppliesTheScreenModeOnce() {
    let h = Harness()
    h.send(.arm, .lidClosed, .lidClosed)
    #expect(h.controller.state == .closed(.persistent))
    #expect(h.screen.closedModes.count == 1)
}

@Test func lidCloseWhileDisarmedOrPausedIsIgnored() {
    let h = Harness()
    h.send(.lidClosed)
    #expect(h.controller.state == .disarmed)
    #expect(h.screen.closedModes.isEmpty)
    #expect(h.flag.calls.isEmpty)

    let paused = Harness()
    paused.env.externalDisplay = true
    paused.send(.arm, .lidClosed)
    #expect(paused.controller.state == .paused)
    #expect(paused.screen.closedModes.isEmpty)
}

@Test func disarmingCancelsTheTransitionGuard() {
    let h = Harness()
    h.send(.arm, .lidClosed, .disarm)
    #expect(!h.assertions.transitionGuard)
    h.scheduler.advance(by: 30)
    #expect(!h.flag.isSet)
    #expect(h.flag.calls.last == false)
}

// A sleep seen by one session must not interrupt the next.
@Test func aSleepDuringAnEndedSessionDoesNotInterruptTheNextOne() {
    let h = Harness()
    h.send(.arm, .lidClosed, .systemWillSleep, .disarm)
    h.notices.removeAll()
    h.send(.arm, .lidClosed, .lidOpened)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.flag.isSet)
    #expect(h.notices.isEmpty)
}

@Test func aSleepBeforeAPauseDoesNotInterruptTheResumedSession() {
    let h = Harness()
    h.settings.safety = SafetySettings()
    h.send(.arm, .lidClosed, .systemWillSleep)
    h.env.externalDisplay = true
    h.send(.environmentChanged)
    #expect(h.controller.state == .paused)
    h.env.externalDisplay = false
    h.send(.environmentChanged)
    h.notices.removeAll()
    h.send(.lidClosed, .lidOpened)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.notices.isEmpty)
}
