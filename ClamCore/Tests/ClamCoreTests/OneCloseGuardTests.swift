import Testing
@testable import ClamCore

@Test func guardNeverCancelsWhenNotOneCloseArmed() {
    #expect(!OneCloseGuard.shouldCancel(oneCloseArmed: false, gestureArmed: false, preferenceOn: false,
                                        secondsSinceGoodSample: 1000))
}

@Test func guardKeepsAHealthyGestureSession() {
    #expect(!OneCloseGuard.shouldCancel(oneCloseArmed: true, gestureArmed: true, preferenceOn: true,
                                        secondsSinceGoodSample: 0.2))
    #expect(!OneCloseGuard.shouldCancel(oneCloseArmed: true, gestureArmed: true, preferenceOn: true,
                                        secondsSinceGoodSample: 10))
}

@Test func guardCancelsWhenTheGestureIsNoLongerTracking() {
    #expect(OneCloseGuard.shouldCancel(oneCloseArmed: true, gestureArmed: false, preferenceOn: true,
                                       secondsSinceGoodSample: 0))
}

@Test func guardCancelsWhenTheSensorHasBeenSilentPastTheStall() {
    #expect(OneCloseGuard.shouldCancel(oneCloseArmed: true, gestureArmed: true, preferenceOn: true,
                                       secondsSinceGoodSample: 10.1))
}

@Test func guardCancelsWhenThePreferenceIsOff() {
    #expect(OneCloseGuard.shouldCancel(oneCloseArmed: true, gestureArmed: true, preferenceOn: false,
                                       secondsSinceGoodSample: 0))
}

@Test func forgettingTheAngleDoesNotLookLikeACrossing() {
    var g = TiltGesture()
    #expect(g.sample(angle: 90, optionHeld: true, at: 0) == .none)
    g.forgetAngle()
    #expect(g.sample(angle: 50, optionHeld: true, at: 1) == .none)
    #expect(!g.isArmed)
}

@Test func forgettingTheAngleKeepsAnArmedGestureArmed() {
    var g = TiltGesture()
    _ = g.sample(angle: 90, optionHeld: true, at: 0)
    #expect(g.sample(angle: 50, optionHeld: true, at: 0.1) == .armOneClose)
    g.forgetAngle()
    #expect(g.isArmed)
}
