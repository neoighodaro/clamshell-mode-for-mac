import Foundation
import IOKit.hid

/// The MacBook lid-angle sensor. Unavailable on Macs without one.
public final class LidAngleSensor {
    private let manager: IOHIDManager
    private let device: IOHIDDevice?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public var isAvailable: Bool { device != nil }

    /// The lid angle in degrees, 0 when shut.
    public func angle() -> Int? {
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess
        else { return nil }
        return Self.decode(Array(report.prefix(length)))
    }

    /// Feature report 1: [report ID, angle low byte, angle high byte]. `nil` if short or above 360 degrees.
    public static func decode(_ report: [UInt8]) -> Int? {
        guard report.count >= 3 else { return nil }
        let degrees = Int(report[1]) | Int(report[2]) << 8
        return degrees <= 360 ? degrees : nil
    }
}
