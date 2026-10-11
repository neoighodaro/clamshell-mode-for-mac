import ClamSignal
import Darwin
import Foundation
import Testing
@testable import ClamCore

private let hardwareTests = ProcessInfo.processInfo.environment["CLAM_HW_TESTS"] == "1"

@Test func emergencyClearWithoutAConnectionDoesNothing() {
    clam_signal_set_connection(0)
    clam_signal_emergency_clear()
}

@Test func terminationSignalIsHandedOffThroughThePipe() {
    #expect(clam_signal_install() == 0)
    let fd = clam_signal_termination_fd()
    #expect(fd >= 0)

    kill(getpid(), SIGHUP)

    var byte: UInt8 = 0
    var count = 0
    for _ in 0..<200 {
        count = read(fd, &byte, 1)
        if count == 1 { break }
        usleep(10_000)
    }
    // Cancel the 5 second alarm the handler armed, or the test process is killed.
    clam_signal_termination_done()
    #expect(count == 1)
    #expect(Int32(byte) == SIGHUP)
}

// Clearing is harmless unless Clamshell.app is armed, so it is opt-in.
// Never add a test that sets the flag to 1.
@Test(.enabled(if: hardwareTests))
func rootDomainConnectionOpensAndClears() {
    let flag = SleepFlag()
    #expect(flag != nil)
    #expect(flag?.set(disabled: false) == true)
    #expect(SleepFlag.clearOnce())
}
