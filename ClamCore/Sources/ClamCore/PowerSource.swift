import Foundation
import IOKit.ps

public struct PowerSample: Equatable, Sendable {
    public var onBattery: Bool
    /// `nil` when no internal battery percentage could be read.
    public var percent: Int?
}

/// Battery state from IOKit power sources. Main-thread only.
public final class PowerSource {
    public var onChange: (() -> Void)?
    /// Consecutive `sample()` calls that returned no percentage.
    public private(set) var missingSamples = 0

    private var runLoopSource: CFRunLoopSource?

    public init() {}

    var isStarted: Bool { runLoopSource != nil }

    public static func track(missing: Int, percent: Int?) -> Int {
        percent == nil ? missing + 1 : 0
    }

    public func sample() -> PowerSample {
        let sample = read()
        missingSamples = Self.track(missing: missingSamples, percent: sample.percent)
        return sample
    }

    /// Begin delivering `onChange` on the main run loop when the power source changes.
    public func start() {
        guard runLoopSource == nil else { return }
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerSource>.fromOpaque(context).takeUnretainedValue().onChange?()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(
            callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    /// Stop delivering `onChange`. Safe to call when not started.
    public func stop() {
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        CFRunLoopSourceInvalidate(source)
        runLoopSource = nil
    }

    deinit {
        stop()
    }

    private func read() -> PowerSample {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSample(onBattery: false, percent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let onBattery = providing == "Battery Power"

        var percent: Int?
        let sources = (IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  info["Type"] as? String == "InternalBattery",
                  let current = info["Current Capacity"] as? Int,
                  let maximum = info["Max Capacity"] as? Int, maximum > 0 else { continue }
            percent = min(100, max(0, current * 100 / maximum))
        }
        return PowerSample(onBattery: onBattery, percent: percent)
    }
}
