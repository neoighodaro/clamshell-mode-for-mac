import Foundation

/// Remembers recent relaunches so the watchdog can stop a crash loop.
public struct CrashLoopGuard {
    private let url: URL
    private let maxRelaunches: Int
    private let window: TimeInterval

    public init(url: URL, maxRelaunches: Int = 3, window: TimeInterval = 300) {
        self.url = url
        self.maxRelaunches = maxRelaunches
        self.window = window
    }

    public func shouldStandDown(at now: Date) -> Bool {
        recent(at: now).count >= maxRelaunches
    }

    public mutating func recordRelaunch(at now: Date) {
        var times = recent(at: now)
        times.append(now.timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(times) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func recent(at now: Date) -> [Double] {
        guard let data = try? Data(contentsOf: url),
              let times = try? JSONDecoder().decode([Double].self, from: data) else { return [] }
        let cutoff = now.timeIntervalSince1970 - window
        return times.filter { $0 > cutoff && $0 <= now.timeIntervalSince1970 }
    }
}
