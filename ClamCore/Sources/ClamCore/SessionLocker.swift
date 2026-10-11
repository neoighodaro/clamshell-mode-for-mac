import AppKit
import CoreGraphics
import Foundation

/// Requests the macOS lock screen and reports whether the session is locked.
public final class SessionLocker: SessionLocking {
    private static let eventClass: AEEventClass = 0x6165_7674   // 'aevt'
    private static let lockEventID: AEEventID = 0x7363_6C6B     // 'sclk'

    /// The error from the most recent failed lock request, for diagnostics.
    public private(set) var lastError: String?

    public init() {}

    /// Sends the lock event to loginwindow. `true` means the request was dispatched, not that the
    /// session locked; callers must poll `isLocked` to confirm.
    public func requestLock() -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(
            eventClass: Self.eventClass, eventID: Self.lockEventID, targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 2)
            lastError = nil
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }

    public var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
