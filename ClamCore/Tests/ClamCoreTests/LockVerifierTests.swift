import Testing
@testable import ClamCore

private final class VerifierHarness {
    let locker = FakeLocker()
    let scheduler = ManualScheduler()
    var results: [Bool] = []
    lazy var verifier = LockVerifier(locker: locker, scheduler: scheduler)

    func verify() {
        verifier.verify { [unowned self] in self.results.append($0) }
    }
}

@Test func verificationSucceedsOnceTheSessionReportsLocked() {
    let h = VerifierHarness()
    h.verify()
    #expect(h.locker.requests == 1)
    h.scheduler.advance(by: 1)
    #expect(h.results.isEmpty)

    h.locker.isLocked = true
    h.scheduler.advance(by: 0.2)
    #expect(h.results == [true])
    // Nothing is left polling.
    h.scheduler.advance(by: 10)
    #expect(h.results == [true])
}

@Test func verificationFailsWhenTheSessionDoesNotLockInThreeSeconds() {
    let h = VerifierHarness()
    h.verify()
    h.scheduler.advance(by: 2.9)
    #expect(h.results.isEmpty)
    h.scheduler.advance(by: 0.2)
    #expect(h.results == [false])

    // A lock that arrives after the limit does not turn the answer around.
    h.locker.isLocked = true
    h.scheduler.advance(by: 10)
    #expect(h.results == [false])
}

@Test func verificationFailsAtOnceWhenTheRequestCannotBeSent() {
    let h = VerifierHarness()
    h.locker.requestSucceeds = false
    h.verify()
    #expect(h.results == [false])
}

@Test func aSecondVerificationWhileOneRunsSharesItsResult() {
    let h = VerifierHarness()
    h.verify()
    h.verify()
    #expect(h.locker.requests == 1)
    h.locker.isLocked = true
    h.scheduler.advance(by: 0.2)
    #expect(h.results == [true, true])

    // A later one starts afresh.
    h.locker.isLocked = false
    h.verify()
    #expect(h.locker.requests == 2)
    h.scheduler.advance(by: 4)
    #expect(h.results == [true, true, false])
}
