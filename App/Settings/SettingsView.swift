import ClamCore
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    private let preferences: Preferences
    let tiltSupported: Bool
    let agentsScreenSupported: Bool

    /// Battery safety or threshold changed; the controller must re-evaluate.
    var onSafetyChanged: (() -> Void)?
    /// The tilt-gesture preference changed; monitoring starts or stops.
    var onTiltGestureChanged: (() -> Void)?
    var onPreviewSound: ((LidSound) -> Void)?
    /// Supplies the current watchdog status text.
    var watchdogStatusProvider: (() -> String)?
    /// Ends any hotkey recording in progress (window closing or reopening).
    var stopRecording: (() -> Void)?
    /// Locks the screen once and reports whether the lock took.
    var verifyLock: ((@escaping (Bool) -> Void) -> Void)?
    /// The hotkey recorder row.
    var hotkeyRow: AnyView?

    @Published var rightClickToggles: Bool { didSet { preferences.rightClickToggles = rightClickToggles } }
    @Published var tiltGestureEnabled: Bool {
        didSet { preferences.tiltGestureEnabled = tiltGestureEnabled; onTiltGestureChanged?() }
    }
    @Published var screenMode: ScreenMode { didSet { applyScreenMode() } }
    /// Progress or the reason for a refusal, shown under the screen-mode picker.
    @Published var lockCheckMessage: String?
    private var checkingLock = false
    @Published var batterySafetyEnabled: Bool {
        didSet { preferences.batterySafetyEnabled = batterySafetyEnabled; onSafetyChanged?() }
    }
    @Published var batteryThreshold: Double {
        didSet { preferences.batteryThreshold = Int(batteryThreshold) }
    }
    @Published var lidSound: LidSound {
        didSet { preferences.lidSound = lidSound; onPreviewSound?(lidSound) }
    }
    @Published var pauseNoticeEnabled: Bool { didSet { preferences.pauseNoticeEnabled = pauseNoticeEnabled } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var launchAtLoginError: String?
    @Published var launchNeedsApproval = false
    @Published var watchdogStatus = ""

    init(preferences: Preferences, tiltSupported: Bool, agentsScreenSupported: Bool) {
        self.preferences = preferences
        self.tiltSupported = tiltSupported
        self.agentsScreenSupported = agentsScreenSupported
        rightClickToggles = preferences.rightClickToggles
        tiltGestureEnabled = preferences.tiltGestureEnabled
        screenMode = preferences.usableScreenMode
        batterySafetyEnabled = preferences.batterySafetyEnabled
        batteryThreshold = Double(preferences.batteryThreshold)
        lidSound = preferences.lidSound
        pauseNoticeEnabled = preferences.pauseNoticeEnabled
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    /// The slider settled; the controller re-evaluates once, not on every drag step.
    func commitThreshold() { onSafetyChanged?() }

    /// Re-read values another part of the app may have changed.
    func reload() {
        // Never the raw saved mode: showing an unverified agents-screen here would start a lock check.
        if !checkingLock {
            lockCheckMessage = nil
            if screenMode != preferences.usableScreenMode { screenMode = preferences.usableScreenMode }
        }
        refreshLaunchAtLogin()
        if let text = watchdogStatusProvider?() { watchdogStatus = text }
    }

    /// Agents-screen mode is saved only after one lock has been seen to work on this Mac.
    private func applyScreenMode() {
        guard screenMode == .agentsScreen, !preferences.lockVerified else {
            preferences.screenMode = screenMode
            if screenMode == .agentsScreen { lockCheckMessage = nil }
            return
        }
        guard !checkingLock else { return }
        guard let verifyLock else {
            refuseAgentsScreen()
            return
        }
        checkingLock = true
        lockCheckMessage = "Locking your screen once to check that Clam can lock this Mac…"
        verifyLock { [weak self] locked in
            guard let self else { return }
            self.checkingLock = false
            guard locked else {
                self.refuseAgentsScreen()
                return
            }
            self.preferences.lockVerified = true
            self.lockCheckMessage = nil
            // The user may have switched back while the check ran.
            if self.screenMode == .agentsScreen { self.preferences.screenMode = .agentsScreen }
        }
    }

    private func refuseAgentsScreen() {
        lockCheckMessage = "Clam could not lock your screen, so \"Agents use the screen\" stays off: it would leave your Mac unlocked when you open the lid."
        if screenMode != .displayOff { screenMode = .displayOff }
    }

    /// Show what the system actually reports, whatever the toggle last asked for.
    private func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
        launchNeedsApproval = status == .requiresApproval
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        let isEnabled = service.status == .enabled
        guard launchAtLogin != isEnabled else { return }
        do {
            if launchAtLogin { try service.register() } else { try service.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        // Read back: a throw or .requiresApproval must not leave the toggle on.
        // (Assigning inside didSet does not re-enter it.)
        let status = service.status
        launchAtLogin = status == .enabled
        launchNeedsApproval = status == .requiresApproval
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Arming") {
                Toggle("Right-click the menu bar icon to toggle", isOn: $model.rightClickToggles)
                if let hotkeyRow = model.hotkeyRow { hotkeyRow }
                Toggle("Hold Option while closing the lid to arm for one close", isOn: $model.tiltGestureEnabled)
                    .disabled(!model.tiltSupported)
                if !model.tiltSupported {
                    Text("This Mac has no lid-angle sensor, so the gesture is unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("While the lid is closed") {
                Picker("Screen", selection: $model.screenMode) {
                    Text("Turn the display off").tag(ScreenMode.displayOff)
                    Text("Agents use the screen").tag(ScreenMode.agentsScreen)
                }
                .disabled(!model.agentsScreenSupported)
                Text("Agents use the screen: the built-in display stays on at zero brightness so screen capture keeps working, and your Mac locks when you open the lid. Choosing it locks your screen once, to check that Clam can lock this Mac. This uses more battery and runs warmer.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = model.lockCheckMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Picker("Lid-close sound", selection: $model.lidSound) {
                    Text("Off").tag(LidSound.off)
                    Text("Chime").tag(LidSound.chime)
                    Text("Latch").tag(LidSound.latch)
                    Text("Shell").tag(LidSound.shell)
                }
            }

            Section("Safety") {
                Toggle("Disarm on low battery", isOn: $model.batterySafetyEnabled)
                Slider(value: $model.batteryThreshold,
                       in: Double(SafetySettings.thresholdRange.lowerBound)...Double(SafetySettings.thresholdRange.upperBound),
                       step: 1,
                       onEditingChanged: { editing in if !editing { model.commitThreshold() } }) {
                    Text("Disarm at \(Int(model.batteryThreshold))%")
                }
                .disabled(!model.batterySafetyEnabled)
                Toggle("Notify when pausing for an external display", isOn: $model.pauseNoticeEnabled)
                Text("Clam always disarms when your Mac runs hot.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                if model.launchNeedsApproval {
                    Text("Approve Clam in System Settings > General > Login Items to finish enabling this.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text(model.watchdogStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
