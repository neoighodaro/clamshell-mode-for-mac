import Testing
@testable import ClamCore

private func verdict(_ state: SessionState, _ change: (inout Environment) -> Void = { _ in },
                     settings: SafetySettings = SafetySettings()) -> SafetyVerdict {
    var env = Environment.nominal
    change(&env)
    return SafetyPolicy.evaluate(state: state, environment: env, settings: settings)
}

private let live: [SessionState] = [.armed(.persistent), .armed(.oneClose), .closed(.persistent), .closed(.oneClose)]

@Test func nominalEnvironmentAllowsEverything() {
    #expect(verdict(.disarmed) == .allow)
    for s in live { #expect(verdict(s) == .allow) }
    #expect(verdict(.paused) == .allow)
}

@Test func thermalSeriousOrCritical() {
    for level in [ThermalLevel.serious, .critical] {
        #expect(verdict(.disarmed) { $0.thermal = level } == .blockArm(.thermal))
        for s in live { #expect(verdict(s) { $0.thermal = level } == .forceDisarm(.thermal)) }
        #expect(verdict(.paused) { $0.thermal = level } == .forceDisarm(.thermal))
    }
    #expect(verdict(.disarmed) { $0.thermal = .fair } == .allow)
}

@Test func lowBatteryOnBatteryOnly() {
    let low: (inout Environment) -> Void = { $0.onBattery = true; $0.batteryPercent = 20 }
    #expect(verdict(.disarmed, low) == .blockArm(.lowBattery(percent: 20)))
    for s in live { #expect(verdict(s, low) == .forceDisarm(.lowBattery(percent: 20))) }
    #expect(verdict(.paused, low) == .forceDisarm(.lowBattery(percent: 20)))
    // Above the threshold, or on AC, is fine.
    #expect(verdict(.armed(.persistent)) { $0.onBattery = true; $0.batteryPercent = 21 } == .allow)
    #expect(verdict(.armed(.persistent)) { $0.onBattery = false; $0.batteryPercent = 3 } == .allow)
}

@Test func batterySafetyCanBeTurnedOff() {
    let off = SafetySettings(batterySafetyEnabled: false)
    #expect(verdict(.armed(.persistent), { $0.onBattery = true; $0.batteryPercent = 2 }, settings: off) == .allow)
    #expect(verdict(.armed(.persistent), { $0.batteryPercent = nil; $0.batteryMissingSamples = 5 }, settings: off) == .allow)
}

@Test func batteryUnreadableNeedsTwoSamples() {
    let once: (inout Environment) -> Void = { $0.batteryPercent = nil; $0.batteryMissingSamples = 1 }
    let twice: (inout Environment) -> Void = { $0.batteryPercent = nil; $0.batteryMissingSamples = 2 }
    #expect(verdict(.armed(.persistent), once) == .allow)
    #expect(verdict(.disarmed, twice) == .blockArm(.batteryUnreadable))
    for s in live { #expect(verdict(s, twice) == .forceDisarm(.batteryUnreadable)) }
    #expect(verdict(.paused, twice) == .forceDisarm(.batteryUnreadable))
}

@Test func topologyUnreadable() {
    let unreadable: (inout Environment) -> Void = { $0.externalDisplay = nil }
    #expect(verdict(.disarmed, unreadable) == .blockArm(.topologyUnreadable))
    for s in live { #expect(verdict(s, unreadable) == .forceDisarm(.topologyUnreadable)) }
    #expect(verdict(.paused, unreadable) == .pause)
}

@Test func externalDisplayPauses() {
    let external: (inout Environment) -> Void = { $0.externalDisplay = true }
    #expect(verdict(.disarmed, external) == .pause)
    for s in live { #expect(verdict(s, external) == .pause) }
    #expect(verdict(.paused, external) == .pause)
}

@Test func rivalBlocksArmingOnly() {
    let rival: (inout Environment) -> Void = { $0.rivalRunning = true }
    #expect(verdict(.disarmed, rival) == .blockArm(.rivalRunning))
    #expect(verdict(.armed(.persistent), rival) == .allow)
}

@Test func hazardsOutrankTheExternalDisplay() {
    #expect(verdict(.armed(.persistent)) { $0.externalDisplay = true; $0.thermal = .critical } == .forceDisarm(.thermal))
}
