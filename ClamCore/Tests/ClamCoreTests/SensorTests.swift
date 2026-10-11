import Testing
@testable import ClamCore

@Test func lidAngleDecodesLittleEndianDegrees() {
    #expect(LidAngleSensor.decode([1, 121, 0]) == 121)
    #expect(LidAngleSensor.decode([1, 0x2C, 0x01]) == 300)
    #expect(LidAngleSensor.decode([1, 0, 0]) == 0)
}

@Test func lidAngleRejectsShortReports() {
    #expect(LidAngleSensor.decode([1, 121]) == nil)
    #expect(LidAngleSensor.decode([]) == nil)
}

@Test func lidAngleRejectsAboveThreeSixty() {
    #expect(LidAngleSensor.decode([1, 0x68, 0x01]) == 360)
    #expect(LidAngleSensor.decode([1, 0x69, 0x01]) == nil)
    #expect(LidAngleSensor.decode([1, 0xFF, 0xFF]) == nil)
}

@Test func displayTopologyRestartsAndReleasesWithoutCrashing() {
    weak var released: DisplayTopology?
    do {
        let topology = DisplayTopology()
        topology.start()
        topology.stop()
        topology.start()
        released = topology
    }
    #expect(released == nil)
}

private func display(_ id: UInt32, builtin: Bool) -> DisplayInfo {
    DisplayInfo(id: id, isBuiltin: builtin, vendor: 0x610, model: 1, serial: 1)
}

@Test func builtinOnly() {
    let s = DisplayTopology.summarize([display(1, builtin: true)])
    #expect(s == DisplaySnapshot(builtin: 1, hasExternal: false))
}

@Test func builtinPlusExternal() {
    let s = DisplayTopology.summarize([display(1, builtin: true), display(2, builtin: false)])
    #expect(s == DisplaySnapshot(builtin: 1, hasExternal: true))
}

@Test func externalOnlyWhenTheLidIsShut() {
    let s = DisplayTopology.summarize([display(2, builtin: false)])
    #expect(s == DisplaySnapshot(builtin: nil, hasExternal: true))
}

@Test func noDisplaysAtAllIsReadableAndHasNoExternal() {
    #expect(DisplayTopology.summarize([]) == DisplaySnapshot(builtin: nil, hasExternal: false))
}
