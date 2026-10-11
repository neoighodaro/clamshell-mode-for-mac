import Foundation

public struct RestoreRecord: Codable, Equatable, Sendable {
    public var brightness: Float
    public var lockOwed: Bool

    public init(brightness: Float, lockOwed: Bool) {
        self.brightness = brightness
        self.lockOwed = lockOwed
    }
}

/// The pending-restore record: present while built-in brightness is zeroed.
public final class RestoreRecordStore {
    /// Used when a record exists but cannot be decoded, or the brightness to save or
    /// restore is unusable. Visible, not blinding.
    public static let fallbackBrightness: Float = 0.6
    /// Below this the built-in display is effectively black: never a level to restore to.
    public static let minimumBrightness: Float = 0.05

    /// `brightness` if it is a level worth restoring to, otherwise `fallbackBrightness`.
    public static func usableBrightness(_ brightness: Float?) -> Float {
        guard let brightness, (minimumBrightness...1).contains(brightness) else { return fallbackBrightness }
        return brightness
    }

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func load() -> RestoreRecord? {
        guard exists else { return nil }
        if let data = try? Data(contentsOf: url),
           let record = try? JSONDecoder().decode(RestoreRecord.self, from: data) {
            return RestoreRecord(brightness: Self.usableBrightness(record.brightness), lockOwed: record.lockOwed)
        }
        return RestoreRecord(brightness: Self.fallbackBrightness, lockOwed: true)
    }

    public func save(_ record: RestoreRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
