import CoreGraphics
import Foundation

/// Built-in display brightness through the private DisplayServices framework.
public final class BrightnessControl: BrightnessControlling {
    typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    /// How far the read-back brightness may differ from the target and still count as written.
    static let readbackTolerance: Float = 0.05

    private let getFunction: GetFunction?
    private let setFunction: SetFunction?
    private let display: () -> UInt32?

    /// `display` returns the built-in display's ID, or `nil` if it is not known.
    public init(display: @escaping () -> UInt32?) {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        let handle = dlopen(path, RTLD_LAZY)
        var get: GetFunction?
        if let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            get = unsafeBitCast(symbol, to: GetFunction.self)
        }
        var set: SetFunction?
        if let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            set = unsafeBitCast(symbol, to: SetFunction.self)
        }
        self.display = display
        getFunction = get
        setFunction = set
    }

    /// Test seam: injects the DisplayServices functions instead of looking them up.
    init(display: @escaping () -> UInt32?, get: GetFunction?, set: SetFunction?) {
        self.display = display
        getFunction = get
        setFunction = set
    }

    /// The brightness functions exist on this macOS. Does not depend on the lid.
    public var isSupported: Bool {
        getFunction != nil && setFunction != nil
    }

    public var isAvailable: Bool {
        isSupported && display() != nil
    }

    public func get() -> Float? {
        guard let getFunction, let id = display() else { return nil }
        var value: Float = 0
        return getFunction(id, &value) == 0 ? value : nil
    }

    /// `true` only when the write returned success and, if the brightness can be read back,
    /// the read-back value is within `readbackTolerance` of the clamped target.
    public func set(_ value: Float) -> Bool {
        guard let setFunction, let id = display() else { return false }
        let target = min(max(value, 0), 1)
        guard setFunction(id, target) == 0 else { return false }
        guard let readback = get() else { return true }
        return abs(readback - target) <= Self.readbackTolerance
    }
}
