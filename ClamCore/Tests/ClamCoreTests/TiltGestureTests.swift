import Testing
@testable import ClamCore

@Test func armsWhenCrossingBelowSixtyWithOptionHeld() {
    var g = TiltGesture()
    #expect(g.sample(angle: 90, optionHeld: true, at: 0) == .none)
    #expect(g.sample(angle: 65, optionHeld: true, at: 0.1) == .none)
    #expect(g.sample(angle: 58, optionHeld: true, at: 0.2) == .armOneClose)
    #expect(g.isArmed)
}

@Test func doesNotArmWithoutOptionAtTheCrossing() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    #expect(g.sample(angle: 55, optionHeld: false, at: 0.1) == .none)
    // Pressing Option once already below 60 does nothing for this close.
    #expect(g.sample(angle: 40, optionHeld: true, at: 0.2) == .none)
    #expect(!g.isArmed)
}

@Test func releasingOptionAfterArmingDoesNotCancel() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    _ = g.sample(angle: 55, optionHeld: true, at: 0.1)
    #expect(g.sample(angle: 30, optionHeld: false, at: 0.2) == .none)
    #expect(g.isArmed)
}

@Test func reopeningByTwentyDegreesCancels() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    _ = g.sample(angle: 55, optionHeld: true, at: 0.1)
    _ = g.sample(angle: 30, optionHeld: true, at: 0.2)
    #expect(g.sample(angle: 49, optionHeld: true, at: 0.3) == .none)
    #expect(g.sample(angle: 50, optionHeld: true, at: 0.4) == .cancel)
    #expect(!g.isArmed)
}

@Test func stallingForTenSecondsCancels() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    _ = g.sample(angle: 55, optionHeld: true, at: 1)
    #expect(g.sample(angle: 55, optionHeld: true, at: 10.9) == .none)
    #expect(g.sample(angle: 55, optionHeld: true, at: 11) == .cancel)
}

@Test func downwardProgressResetsTheStallClock() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    _ = g.sample(angle: 55, optionHeld: true, at: 1)
    _ = g.sample(angle: 40, optionHeld: true, at: 9)
    #expect(g.sample(angle: 40, optionHeld: true, at: 18) == .none)
    #expect(g.sample(angle: 40, optionHeld: true, at: 19) == .cancel)
}

@Test func jitterAroundTheThresholdArmsOnlyOnce() {
    var g = TiltGesture()
    _ = g.sample(angle: 61, optionHeld: true, at: 0)
    #expect(g.sample(angle: 59, optionHeld: true, at: 0.1) == .armOneClose)
    #expect(g.sample(angle: 61, optionHeld: true, at: 0.2) == .none)
    #expect(g.sample(angle: 59, optionHeld: true, at: 0.3) == .none)
}

@Test func firstSampleBelowThresholdDoesNotArm() {
    var g = TiltGesture()
    #expect(g.sample(angle: 30, optionHeld: true, at: 0) == .none)
}

@Test func resetAllowsANewGesture() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    _ = g.sample(angle: 55, optionHeld: true, at: 0.1)
    g.reset()
    #expect(!g.isArmed)
    #expect(g.sample(angle: 70, optionHeld: true, at: 5) == .none)
    #expect(g.sample(angle: 55, optionHeld: true, at: 5.1) == .armOneClose)
}

// A sensor that reads only every other tick: each gap forgets the previous angle.
@Test func missedSamplesDoNotDefeatTheStallCancel() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    #expect(g.sample(angle: 55, optionHeld: true, at: 1) == .armOneClose)
    g.forgetAngle()
    #expect(g.sample(angle: 55, optionHeld: true, at: 6) == .none)
    g.forgetAngle()
    #expect(g.sample(angle: 55, optionHeld: true, at: 11) == .cancel)
    #expect(!g.isArmed)
}

@Test func missedSamplesDoNotDefeatTheReverseCancel() {
    var g = TiltGesture()
    _ = g.sample(angle: 70, optionHeld: true, at: 0)
    #expect(g.sample(angle: 55, optionHeld: true, at: 0.1) == .armOneClose)
    g.forgetAngle()
    #expect(g.sample(angle: 75, optionHeld: true, at: 0.3) == .cancel)
}
