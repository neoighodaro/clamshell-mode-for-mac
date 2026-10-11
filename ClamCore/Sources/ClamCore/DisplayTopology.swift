import CoreGraphics
import Foundation

public struct DisplayInfo: Equatable, Sendable {
    public var id: UInt32
    public var isBuiltin: Bool
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32

    public init(id: UInt32, isBuiltin: Bool, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.id = id
        self.isBuiltin = isBuiltin
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public var builtin: UInt32?
    public var hasExternal: Bool

    public init(builtin: UInt32?, hasExternal: Bool) {
        self.builtin = builtin
        self.hasExternal = hasExternal
    }
}

/// A file-scope function, so the same pointer can be passed to register and remove.
private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                 _ context: UnsafeMutableRawPointer?) {
    guard let context, !flags.contains(.beginConfigurationFlag) else { return }
    // Only a weak reference crosses to the main queue; a released topology is skipped.
    let topology = Unmanaged<DisplayTopology>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { [weak topology] in topology?.onChange?() }
}

/// Which displays are online. Main-thread only.
public final class DisplayTopology {
    /// Fires on the main queue after any display reconfiguration (add, remove, mode or arrangement change).
    public var onChange: (() -> Void)?
    /// The built-in display's ID, remembered while the lid is shut and it drops off the list.
    public private(set) var lastBuiltin: UInt32?

    private var started = false

    public init() {}

    deinit {
        stop()
    }

    /// `nil` when CoreGraphics cannot list the displays.
    public func list() -> [DisplayInfo]? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        if count > 0 {
            guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        }
        return ids.prefix(Int(count)).map {
            DisplayInfo(id: $0, isBuiltin: CGDisplayIsBuiltin($0) != 0,
                        vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0),
                        serial: CGDisplaySerialNumber($0))
        }
    }

    public func snapshot() -> DisplaySnapshot? {
        guard let displays = list() else { return nil }
        let summary = Self.summarize(displays)
        if let builtin = summary.builtin { lastBuiltin = builtin }
        return summary
    }

    /// Begin delivering `onChange` on the main queue on display reconfiguration. Idempotent.
    public func start() {
        guard !started else { return }
        started = true
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Stop delivering `onChange`. Idempotent.
    public func stop() {
        guard started else { return }
        started = false
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    public static func summarize(_ displays: [DisplayInfo]) -> DisplaySnapshot {
        DisplaySnapshot(builtin: displays.first(where: \.isBuiltin)?.id,
                        hasExternal: displays.contains(where: countsAsExternal))
    }

    /// Whether a display should pause Clam in favour of native clamshell mode.
    public static func countsAsExternal(_ display: DisplayInfo) -> Bool {
        !display.isBuiltin
    }
}
