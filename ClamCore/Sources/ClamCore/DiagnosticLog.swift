import Darwin
import Foundation

/// Append-only text log. When it exceeds `maxBytes` the older half is dropped.
public final class DiagnosticLog {
    private let url: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "co.creativitykills.clam.log")
    private let formatter = ISO8601DateFormatter()

    public init(url: URL, maxBytes: Int = 1_000_000) {
        self.url = url
        self.maxBytes = maxBytes
    }

    public func log(_ message: String) {
        queue.sync {
            let line = Data("\(formatter.string(from: Date())) \(message)\n".utf8)
            // O_APPEND: the app and the watchdog both write here, and neither may drop the other's lines.
            let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
            guard fd >= 0 else { return }
            line.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
            let size = Int(lseek(fd, 0, SEEK_END))
            close(fd)
            if size > maxBytes { trim() }
        }
    }

    /// Rewrites the file with its newer half. Rare: once per `maxBytes / 2` of output.
    private func trim() {
        guard let data = try? Data(contentsOf: url) else { return }
        let keepFrom = data.count - maxBytes / 2
        guard keepFrom > 0 else { return }
        // Cut at a line boundary so the file stays readable.
        let kept: Data
        if let newline = data[keepFrom...].firstIndex(of: UInt8(ascii: "\n")), newline + 1 < data.count {
            kept = data.subdata(in: (newline + 1)..<data.count)
        } else {
            kept = data.subdata(in: keepFrom..<data.count)
        }
        try? kept.write(to: url, options: .atomic)
    }
}
