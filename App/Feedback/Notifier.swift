import ClamCore
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Without this, macOS hides banners while Clam is frontmost, e.g. with Settings open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func post(_ notice: SessionNotice) {
        let text = Self.text(for: notice)
        post(text.title, text.body)
    }

    func post(_ notice: ScreenNotice) {
        let text = Self.text(for: notice)
        post(text.title, text.body)
    }

    static func describe(_ reason: SafetyReason) -> String {
        switch reason {
        case .thermal: return "your Mac is running hot"
        case .lowBattery(let percent): return "the battery is at \(percent)%"
        case .batteryUnreadable: return "the battery level could not be read"
        case .topologyUnreadable: return "the connected displays could not be read"
        case .rivalRunning: return "Clamshell is running and controls the same setting"
        }
    }

    static func text(for notice: SessionNotice) -> (title: String, body: String) {
        switch notice {
        case .armFailed:
            return ("Clam could not arm", "macOS rejected the request. Your Mac will sleep when the lid closes.")
        case .armBlocked(let reason):
            return ("Clam did not arm", "Arming is blocked because \(describe(reason)).")
        case .forcedDisarm(let reason):
            return ("Clam disarmed", "Clam disarmed because \(describe(reason)). Your Mac will sleep when the lid closes.")
        case .reapplyFailed:
            return ("Clam disarmed", "macOS stopped accepting the closed-lid setting. Your Mac will sleep when the lid closes.")
        case .clearFailed:
            return ("Clam could not restore lid sleep",
                    "Your Mac may stay awake with the lid closed. Clam keeps retrying; restarting your Mac also resets it.")
        case .clearRecovered:
            return ("Lid sleep restored", "Your Mac will sleep when the lid closes.")
        case .pausedForExternalDisplay:
            return ("Clam paused", "An external display is connected, so macOS handles the closed lid. Clam re-arms when it disconnects.")
        case .resumeFailed:
            return ("Clam could not re-arm", "The external display disconnected but macOS rejected the request. Your Mac will sleep when the lid closes.")
        case .sessionInterrupted(let reason):
            let detail = reason.map { " (\($0))" } ?? ""
            return ("Clam session interrupted", "Your Mac went to sleep while the lid was closed\(detail). Clam is disarmed.")
        case .rivalLaunched:
            return ("Clam disarmed", "Clamshell launched and controls the same setting. Quit it to use Clam.")
        }
    }

    static func text(for notice: ScreenNotice) -> (title: String, body: String) {
        switch notice {
        case .displayMayStayLit:
            return ("Display may stay lit", "Clam could not turn the display off after the lid closed.")
        case .agentsScreenUnavailable:
            return ("Agents-screen mode unavailable", "Brightness control is not available on this Mac. Clam turned the display off instead.")
        case .couldNotPersist:
            return ("Agents-screen mode unavailable", "Clam could not save the brightness to restore, so it turned the display off instead.")
        case .lockNotVerified:
            return ("Agents-screen mode is off", "Clam has not checked that it can lock this Mac, so it turned the display off instead. Choose the mode again in Settings.")
        case .darkenFailed:
            return ("Display may stay lit", "Clam could not set the display brightness to zero.")
        case .lockUnconfirmed:
            return ("Screen lock could not be confirmed", "Clam restored the display and turned agents-screen mode off. Lock your Mac manually before leaving it unattended.")
        case .restoreFailed:
            return ("Display brightness not restored", "The built-in display may still be dark. Press the brightness-up key; Clam tries again the next time the lid opens.")
        }
    }
}
