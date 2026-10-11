import Foundation
import Testing
@testable import ClamCore

@Test func brightnessIsUnavailableWithoutABuiltinDisplay() {
    let control = BrightnessControl(display: { nil })
    #expect(!control.isAvailable)
    #expect(control.get() == nil)
    #expect(!control.set(0.5))
}

@Test func displaySleeperReportsTheCommandsExitStatus() {
    #expect(PmsetDisplaySleeper(executable: "/usr/bin/true", arguments: [], timeout: 2).sleepDisplay())
    #expect(!PmsetDisplaySleeper(executable: "/usr/bin/false", arguments: [], timeout: 2).sleepDisplay())
    #expect(!PmsetDisplaySleeper(executable: "/nonexistent/command", arguments: [], timeout: 2).sleepDisplay())
}

@Test func displaySleeperGivesUpOnACommandThatHangs() {
    let sleeper = PmsetDisplaySleeper(executable: "/bin/sleep", arguments: ["30"], timeout: 0.2)
    let started = Date()
    #expect(!sleeper.sleepDisplay())
    #expect(Date().timeIntervalSince(started) < 5)
}

// C function pointers cannot capture, so the fakes below read and write these globals.
// The suite is serialized because the globals are shared.
private var fakeReadback: Float = 0
private var fakeReadbackRC: Int32 = 0
private var fakeSetRC: Int32 = 0

private let fakeGet: BrightnessControl.GetFunction = { _, out in
    out.pointee = fakeReadback
    return fakeReadbackRC
}
private let fakeSet: BrightnessControl.SetFunction = { _, _ in fakeSetRC }

@Suite(.serialized) struct BrightnessSetTests {
    private func control() -> BrightnessControl {
        BrightnessControl(display: { 1 }, get: fakeGet, set: fakeSet)
    }

    @Test func setSucceedsWhenReadbackMatchesTheTarget() {
        fakeSetRC = 0
        fakeReadbackRC = 0
        fakeReadback = 0.5
        #expect(control().set(0.5))
    }

    @Test func setFailsWhenReadbackIsFarFromTheTarget() {
        fakeSetRC = 0
        fakeReadbackRC = 0
        fakeReadback = 0.2
        #expect(!control().set(0.5))
    }

    @Test func setTrustsTheReturnCodeWhenReadbackIsUnavailable() {
        fakeSetRC = 0
        fakeReadbackRC = -1
        #expect(control().set(0.5))
    }

    @Test func setFailsOnANonzeroReturnCode() {
        fakeSetRC = -1
        fakeReadbackRC = 0
        fakeReadback = 0.5
        #expect(!control().set(0.5))
    }
}
