import Testing
@testable import ClamCore

@Test func thermalTripWhileArmedForcesDisarm() {
    let h = Harness()
    h.send(.arm)
    h.env.thermal = .critical
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
    #expect(h.notices == [.forcedDisarm(.thermal)])
}

@Test func lowBatteryWhileClosedForcesDisarmAndClearsTheFlag() {
    let h = Harness()
    h.send(.arm, .lidClosed)
    h.env.lidClosed = true
    h.env.onBattery = true
    h.env.batteryPercent = 15
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
    #expect(!h.assertions.keepAwake)
    #expect(!h.assertions.transitionGuard)
    #expect(h.notices == [.forcedDisarm(.lowBattery(percent: 15))])
}

// Repeated samples at the threshold.
@Test func repeatedSamplesProduceOneForcedDisarmNotice() {
    let h = Harness()
    h.send(.arm)
    h.env.onBattery = true
    h.env.batteryPercent = 20
    h.send(.environmentChanged, .environmentChanged, .environmentChanged)
    h.env.batteryPercent = 21
    h.send(.environmentChanged)
    h.env.batteryPercent = 20
    h.send(.environmentChanged)
    #expect(h.notices == [.forcedDisarm(.lowBattery(percent: 20))])
    #expect(h.controller.state == .disarmed)
}

@Test func externalDisplayPausesAPersistentArmAndClearsTheFlag() {
    let h = Harness()
    h.send(.arm)
    h.env.externalDisplay = true
    h.send(.environmentChanged)
    #expect(h.controller.state == .paused)
    #expect(!h.flag.isSet)
    #expect(!h.assertions.keepAwake)
    #expect(h.notices == [.pausedForExternalDisplay])
}

@Test func externalDisplayDropsAOneCloseArm() {
    let h = Harness()
    h.send(.tiltArm)
    h.env.externalDisplay = true
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
}

@Test func externalDisplayWhileClosedPauses() {
    let h = Harness()
    h.send(.arm, .lidClosed)
    h.env.lidClosed = true
    h.env.externalDisplay = true
    h.send(.environmentChanged)
    #expect(h.controller.state == .paused)
    #expect(!h.flag.isSet)
}

@Test func disconnectWithTheLidOpenResumesArmed() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm)
    h.env.externalDisplay = false
    h.send(.environmentChanged)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.flag.isSet)
    #expect(h.assertions.keepAwake)
}

@Test func disconnectWithTheLidShutResumesClosedUnderTheGuard() {
    let h = Harness()
    h.settings.screenMode = .agentsScreen
    h.env.externalDisplay = true
    h.env.lidClosed = true
    h.send(.arm)
    h.env.externalDisplay = false
    h.send(.environmentChanged)
    #expect(h.controller.state == .closed(.persistent))
    #expect(h.flag.isSet)
    #expect(h.assertions.transitionGuard)
    #expect(h.screen.closedModes == [.agentsScreen])
}

@Test func failedResumeDisarms() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm)
    h.flag.setSucceeds = false
    h.env.externalDisplay = false
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(!h.assertions.transitionGuard)
    #expect(h.notices == [.pausedForExternalDisplay, .resumeFailed])
}

@Test func hazardWhilePausedCancelsTheRearm() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm)
    h.env.thermal = .serious
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    h.env.thermal = .nominal
    h.env.externalDisplay = false
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(h.flag.calls.allSatisfy { $0 == false })
}

@Test func unreadableTopologyWhilePausedStaysPaused() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm)
    h.env.externalDisplay = nil
    h.send(.environmentChanged)
    #expect(h.controller.state == .paused)
}

@Test func environmentChangeWhileDisarmedDoesNothing() {
    let h = Harness()
    h.env.thermal = .critical
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(h.notices.isEmpty)
    #expect(h.flag.calls.isEmpty)
}

@Test func sleepWithTheLidOpenSurvivesAndReappliesOnWake() {
    let h = Harness()
    h.send(.arm, .systemWillSleep, .systemDidWake)
    #expect(h.controller.state == .armed(.persistent))
    #expect(h.flag.calls == [true, true])
    #expect(h.notices.isEmpty)
}

@Test func sleepWhileClosedEndsTheSession() {
    let h = Harness()
    h.sleepReason = "Low Power Sleep"
    h.send(.arm, .lidClosed)
    h.env.lidClosed = true
    h.send(.systemWillSleep, .systemDidWake)
    #expect(h.controller.state == .disarmed)
    #expect(!h.flag.isSet)
    #expect(h.notices == [.sessionInterrupted(reason: "Low Power Sleep")])
    // Lid still shut on wake: nothing to restore yet.
    #expect(h.screen.restoreCalls == [false])
}

// On wake the app refreshes the lid before it sends the wake event, so the open arrives first.
@Test func lidOpenBeforeTheWakeEventStillReportsTheInterruptedSession() {
    for arm in [SessionEvent.tiltArm, .arm] {
        let h = Harness()
        h.sleepReason = "Low Power Sleep"
        h.send(arm, .lidClosed)
        h.env.lidClosed = true
        h.send(.systemWillSleep)
        h.env.lidClosed = false
        h.send(.lidOpened, .systemDidWake)
        #expect(h.controller.state == .disarmed)
        #expect(!h.flag.isSet)
        #expect(h.notices == [.sessionInterrupted(reason: "Low Power Sleep")])
    }
}

@Test func endingAClosedSessionWithoutALidOpenReleasesTheDisplayAssertion() {
    let h = Harness()
    h.send(.arm, .lidClosed)
    h.env.lidClosed = true
    h.assertions.setDisplayAwake(true)   // taken by the real ScreenController in agents-screen mode
    h.env.externalDisplay = true
    h.send(.environmentChanged)
    #expect(h.controller.state == .paused)
    #expect(!h.assertions.displayAwake)
}

@Test func wakeWithTheLidOpenProcessesAPendingRestore() {
    let h = Harness()
    h.send(.systemDidWake)
    #expect(h.screen.restoreCalls == [true])
}

@Test func sleepWhilePausedDoesNothing() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm, .systemWillSleep, .systemDidWake)
    #expect(h.controller.state == .paused)
    #expect(h.flag.calls.isEmpty)
}

@Test func rivalLaunchDisarms() {
    let h = Harness()
    h.send(.arm, .rivalLaunched)
    #expect(h.controller.state == .disarmed)
    #expect(!h.assertions.keepAwake)
    #expect(h.notices == [.rivalLaunched])

    let idle = Harness()
    idle.send(.rivalLaunched)
    #expect(idle.notices.isEmpty)
}

@Test func rivalRunningBlocksArming() {
    let h = Harness()
    h.env.rivalRunning = true
    h.send(.arm)
    #expect(h.controller.state == .disarmed)
    #expect(h.notices == [.armBlocked(.rivalRunning)])
    #expect(h.flag.calls.isEmpty)
}

@Test func failedResumeWithTheLidShutDisarms() {
    let h = Harness()
    h.env.externalDisplay = true
    h.send(.arm)
    h.env.lidClosed = true
    h.flag.setSucceeds = false
    h.env.externalDisplay = false
    h.send(.environmentChanged)
    #expect(h.controller.state == .disarmed)
    #expect(!h.assertions.transitionGuard)
    #expect(h.screen.closedModes.isEmpty)
    #expect(h.notices == [.pausedForExternalDisplay, .resumeFailed])
}
