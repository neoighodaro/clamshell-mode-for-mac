import Foundation
import IOKit.pwr_mgt

public final class PowerAssertions: PowerAsserting {
    // IOPMLib.h defines these as CFSTR macros, which Swift does not import.
    private enum Kind: String {
        case keepAwake = "PreventUserIdleSystemSleep"
        case transitionGuard = "PreventSystemSleep"
        case displayAwake = "PreventUserIdleDisplaySleep"

        var reason: String {
            switch self {
            case .keepAwake: return "Clam: keeping Mac awake"
            case .transitionGuard: return "Clam: protecting closed-lid power transitions"
            case .displayAwake: return "Clam: keeping the display available to agents"
            }
        }
    }

    private var held: [Kind: IOPMAssertionID] = [:]
    /// Called with a description when macOS refuses to create an assertion.
    public var onCreateFailure: ((String) -> Void)?

    public init() {}

    deinit {
        held.values.forEach { IOPMAssertionRelease($0) }
    }

    public var activeCount: Int { held.count }

    public func setKeepAwake(_ on: Bool) { set(.keepAwake, on) }
    public func setTransitionGuard(_ on: Bool) { set(.transitionGuard, on) }
    public func setDisplayAwake(_ on: Bool) { set(.displayAwake, on) }

    private func set(_ kind: Kind, _ on: Bool) {
        if on {
            guard held[kind] == nil else { return }
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kind.rawValue as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     kind.reason as CFString, &id)
            if result == kIOReturnSuccess {
                held[kind] = id
            } else {
                onCreateFailure?("\(kind.rawValue) (0x\(String(UInt32(bitPattern: result), radix: 16)))")
            }
        } else if let id = held.removeValue(forKey: kind) {
            IOPMAssertionRelease(id)
        }
    }
}
