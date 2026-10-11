import Foundation
import Testing
@testable import ClamCore

@Test func assertionsAreCreatedOnceAndReleased() {
    let assertions = PowerAssertions()
    #expect(assertions.activeCount == 0)
    assertions.setKeepAwake(true)
    assertions.setKeepAwake(true)
    #expect(assertions.activeCount == 1)
    assertions.setTransitionGuard(true)
    assertions.setDisplayAwake(true)
    #expect(assertions.activeCount == 3)
    assertions.setKeepAwake(false)
    assertions.setTransitionGuard(false)
    assertions.setDisplayAwake(false)
    assertions.setDisplayAwake(false)
    #expect(assertions.activeCount == 0)
}

@Test func missingBatterySamplesAreCountedConsecutively() {
    #expect(PowerSource.track(missing: 0, percent: nil) == 1)
    #expect(PowerSource.track(missing: 1, percent: nil) == 2)
    #expect(PowerSource.track(missing: 2, percent: 50) == 0)
}

@Test func powerSampleIsPlausible() {
    let source = PowerSource()
    let sample = source.sample()
    if let percent = sample.percent {
        #expect((0...100).contains(percent))
        #expect(source.missingSamples == 0)
    } else {
        #expect(source.missingSamples == 1)
    }
}

@Test func powerSourceStartAndStopAreIdempotent() {
    let source = PowerSource()
    #expect(!source.isStarted)
    source.start()
    source.start()
    #expect(source.isStarted)
    source.stop()
    source.stop()
    #expect(!source.isStarted)
    // Left started: deinit must remove the run-loop source.
    source.start()
    #expect(source.isStarted)
}

@Test func thermalStatesMap() {
    #expect(ThermalLevel(ProcessInfo.ThermalState.nominal) == .nominal)
    #expect(ThermalLevel(ProcessInfo.ThermalState.fair) == .fair)
    #expect(ThermalLevel(ProcessInfo.ThermalState.serious) == .serious)
    #expect(ThermalLevel(ProcessInfo.ThermalState.critical) == .critical)
}
