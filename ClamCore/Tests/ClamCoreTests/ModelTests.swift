import Testing
@testable import ClamCore

@Test func batteryThresholdIsClampedToRange() {
    #expect(SafetySettings(batteryThreshold: 1).batteryThreshold == 5)
    #expect(SafetySettings(batteryThreshold: 20).batteryThreshold == 20)
    #expect(SafetySettings(batteryThreshold: 99).batteryThreshold == 50)
}

@Test func defaultsMatchTheSpec() {
    let s = SafetySettings()
    #expect(s.batterySafetyEnabled)
    #expect(s.batteryThreshold == 20)
}

@Test func armedAndClosedCountAsArmedOrClosed() {
    #expect(SessionState.armed(.persistent).isArmedOrClosed)
    #expect(SessionState.closed(.oneClose).isArmedOrClosed)
    #expect(!SessionState.disarmed.isArmedOrClosed)
    #expect(!SessionState.paused.isArmedOrClosed)
}

@Test func thermalLevelsAreOrdered() {
    #expect(ThermalLevel.serious > ThermalLevel.fair)
    #expect(ThermalLevel.critical > ThermalLevel.serious)
}
