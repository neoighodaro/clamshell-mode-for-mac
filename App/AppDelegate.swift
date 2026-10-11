import AppKit
import ClamCore
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    let preferences = Preferences()
    let notifier = Notifier()
    var log: DiagnosticLog!
    var pidFile: PidFile!
    var monitor: EnvironmentMonitor!
    var screen: ScreenController!
    var statusItem: StatusItemController!
    private(set) var controller: SessionController!
    private var instanceLock: InstanceLock?
    private var flag: SleepFlag!
    private var assertions: PowerAssertions!
    private var store: RestoreRecordStore!
    private let signals = SignalBridge()
    private let locker = SessionLocker()
    private var terminating = false
    let watchdog = WatchdogManager()
    private var warnedAboutProtection = false
    private var launchClearFailed = false
    /// True only when this launch wrote its pid file; without one the watchdog has nothing to watch.
    private var pidFileWritten = false
    var settingsModel: SettingsModel!
    private var settingsWindow: SettingsWindowController!
    private let soundPlayer = LidSoundPlayer()
    private let hotkeys = HotkeyManager()
    private var hotkeyRecorder: HotkeyRecorderModel!
    private var tiltMonitor: TiltMonitor!
    private let overlay = GestureOverlay()

    /// Set when a clean quit leaves the pending-restore record behind (lid shut at quit).
    private static let cleanQuitLeftRestoreKey = "cleanQuitLeftRestore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = EnvironmentMonitor()
        self.monitor = monitor

        // Step 1: single instance.
        guard let directory = try? ClamPaths.directory() else {
            failLaunch("Clam could not create its folder in Application Support.")
        }
        log = DiagnosticLog(url: ClamPaths.log(in: directory))
        guard let lock = InstanceLock(url: ClamPaths.lockFile(in: directory)) else {
            log.log("duplicate instance; exiting without touching the flag")
            exit(0)
        }
        instanceLock = lock
        notifier.requestAuthorization()
        log.log("launch pid \(getpid())")

        guard let flag = SleepFlag() else {
            failLaunch("Clam could not reach macOS power management, so it cannot keep your Mac awake with the lid closed.")
        }
        self.flag = flag

        // Step 2: clear a flag a previous instance may have left set.
        if EnvironmentMonitor.rivalIsRunning {
            log.log("Clamshell is running; skipping the launch-time clear")
        } else {
            launchClearFailed = !flag.set(disabled: false)
            log.log("launch-time clear: \(launchClearFailed ? "FAILED" : "ok")")
        }

        // Step 3: pid file.
        pidFile = PidFile(url: ClamPaths.pidFile(in: directory))
        if let record = ProcessInspector.currentRecord() {
            do {
                try pidFile.write(record)
                pidFileWritten = true
            } catch {
                log.log("pid file write FAILED: \(error); no relaunch protection")
            }
        } else {
            log.log("pid record unavailable; no relaunch protection")
        }

        // Step 4: crash signals clear the flag and re-raise; termination signals quit cleanly.
        flag.publishToSignalHandlers()
        if !signals.install(onTermination: { NSApp.terminate(nil) }) {
            log.log("signal handlers FAILED to install")
        }

        // Step 5: the watchdog exits when it has nothing to watch, so start it on every launch.
        watchdog.ensureRunning(pidFilePresent: { [weak self] in self?.pidFile?.exists == true }) { [weak self] health in
            guard let self else { return }
            self.log.log("watchdog: \(health)")
            self.statusItem?.relaunchProtected = health == .running && self.pidFileWritten
            self.settingsModel?.watchdogStatus = self.watchdog.statusText
        }

        // Composition.
        let assertions = PowerAssertions()
        assertions.onCreateFailure = { [weak self] in self?.log.log("power assertion FAILED: \($0)") }
        self.assertions = assertions
        let scheduler = MainQueueScheduler()
        let store = RestoreRecordStore(url: ClamPaths.restoreRecord(in: directory))
        self.store = store
        let brightness = BrightnessControl(display: { monitor.displays.lastBuiltin })
        let screen = ScreenController(brightness: brightness, locker: locker,
                                      sleeper: PmsetDisplaySleeper(), store: store,
                                      assertions: assertions, scheduler: scheduler,
                                      lockVerified: { [preferences] in preferences.lockVerified })
        self.screen = screen
        let controller = SessionController(
            flag: flag, assertions: assertions, screen: screen, scheduler: scheduler,
            environment: { monitor.current },
            settings: { [preferences] in preferences.sessionSettings },
            sleepReason: { monitor.lid.lastSleepReason() })
        self.controller = controller
        let statusItem = StatusItemController(controller: controller, preferences: preferences)
        self.statusItem = statusItem
        if !pidFileWritten { statusItem.relaunchProtected = false }
        let settingsModel = SettingsModel(preferences: preferences,
                                          tiltSupported: LidAngleSensor().isAvailable,
                                          agentsScreenSupported: brightness.isSupported)
        self.settingsModel = settingsModel
        settingsModel.onSafetyChanged = { [weak self] in
            self?.monitor.refresh()
            self?.controller.handle(.environmentChanged)
        }
        settingsModel.onPreviewSound = { [soundPlayer] in soundPlayer.play($0) }
        let lockVerifier = LockVerifier(locker: locker, scheduler: scheduler)
        settingsModel.verifyLock = { [weak self] completion in
            lockVerifier.verify { locked in
                self?.log.log("lock verification: \(locked ? "ok" : "FAILED") error=\(self?.locker.lastError ?? "none")")
                completion(locked)
            }
        }
        settingsWindow = SettingsWindowController(model: settingsModel)
        statusItem.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsModel.watchdogStatus = self.watchdog.statusText
            self.settingsWindow.show()
        }
        // Through monitor.onEvent so a toggle refreshes the environment first, like every arm.
        hotkeys.onPress = { [weak self] in self?.monitor.onEvent?(.toggle) }
        var hotkeyActive = false
        if let saved = preferences.hotkey {
            hotkeyActive = hotkeys.register(saved)
            if !hotkeyActive {
                log.log("hotkey registration FAILED for \(saved.displayString)")
                notifier.post("Shortcut unavailable",
                              "\(saved.displayString) could not be registered. Record a new one in Settings.")
            }
        }
        let recorder = HotkeyRecorderModel(binding: preferences.hotkey, isActive: hotkeyActive)
        recorder.onSuspend = { [weak self] in self?.hotkeys.unregister() }
        recorder.onRestore = { [weak self] in self?.hotkeys.register($0) ?? false }
        recorder.onRecord = { [weak self] binding in
            guard let self, self.hotkeys.register(binding) else { return false }
            self.preferences.hotkey = binding
            return true
        }
        recorder.onClear = { [weak self] in
            self?.hotkeys.unregister()
            self?.preferences.hotkey = nil
        }
        settingsModel.stopRecording = { [weak recorder] in recorder?.cancelRecording() }
        settingsModel.watchdogStatusProvider = { [weak self] in self?.watchdog.statusText ?? "" }
        hotkeyRecorder = recorder
        settingsModel.hotkeyRow = AnyView(HotkeyRecorder(model: recorder))
        statusItem.debugItems = [
            ("Lock Now", { [weak self] in
                guard let self else { return }
                let sent = self.locker.requestLock()
                self.log.log("debug lock: sent=\(sent) error=\(self.locker.lastError ?? "none")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.log.log("debug lock: locked after 2s=\(self.locker.isLocked)")
                }
            }),
        ]

        screen.onNotice = { [weak self] notice in
            self?.log.log("screen notice: \(notice)")
            if notice == .lockUnconfirmed {
                // The lock did not take at a lid open, so it is no longer proven. The mode
                // stays off until the user selects it again and the check passes.
                self?.preferences.lockVerified = false
                self?.preferences.screenMode = .displayOff
                self?.settingsModel?.reload()
            }
            self?.notifier.post(notice)
        }
        controller.onNotice = { [weak self] notice in
            guard let self else { return }
            self.log.log("notice: \(notice)")
            self.statusItem.refresh()
            if notice == .pausedForExternalDisplay, !self.preferences.pauseNoticeEnabled { return }
            self.notifier.post(notice)
        }
        controller.onStateChange = { [weak self] old, new in
            self?.log.log("state \(old) -> \(new)")
            self?.statusItem.refresh()
            if new == .armed(.oneClose) { self?.overlay.show() } else { self?.overlay.hide() }
            guard let self else { return }
            if case .armed = old, case .closed = new {
                self.soundPlayer.play(self.preferences.lidSound)
            }
            if old == .disarmed, new != .disarmed {
                // Re-check at each arm; warn once per launch if there is no protection.
                self.watchdog.ensureRunning(pidFilePresent: { self.pidFile?.exists == true }) { health in
                    let protected = health == .running && self.pidFileWritten
                    self.statusItem.relaunchProtected = protected
                    self.settingsModel?.watchdogStatus = self.watchdog.statusText
                    if !protected, !self.warnedAboutProtection {
                        self.warnedAboutProtection = true
                        let text = self.pidFileWritten ? self.watchdog.statusText
                            : "Relaunch protection is unavailable (Clam could not write its pid file)."
                        self.notifier.post("No relaunch protection", text)
                    }
                }
            }
        }
        statusItem.refreshEnvironment = { [weak monitor] in monitor?.refresh() }
        monitor.onEvent = { [weak self] event in
            if event == .arm || event == .toggle || event == .tiltArm { self?.monitor.refresh() }
            self?.controller.handle(event)
        }
        monitor.start()

        // Polling follows the preference, live: Settings toggles it without a relaunch.
        let tiltMonitor = TiltMonitor(controller: controller, preferences: preferences, monitor: monitor)
        self.tiltMonitor = tiltMonitor
        tiltMonitor.isTerminating = { [weak self] in self?.terminating ?? true }
        settingsModel.onTiltGestureChanged = { [weak tiltMonitor] in tiltMonitor?.apply() }
        tiltMonitor.apply()

        // A failed launch-time clear goes through the controller's notice-and-retry path.
        // It skips itself while the rival app is running.
        if launchClearFailed { controller.clearAtLaunch() }

        // Step 6: a record left behind means the last closed-lid agents-screen session
        // did not end with a lid open. Only an unclean end switches the mode off; a clean
        // quit with the lid shut leaves the record on purpose.
        let cleanQuit = UserDefaults.standard.bool(forKey: Self.cleanQuitLeftRestoreKey)
        UserDefaults.standard.removeObject(forKey: Self.cleanQuitLeftRestoreKey)
        if store.exists {
            log.log("pending-restore record found at launch (\(cleanQuit ? "left by a clean quit" : "unclean end"))")
            if !cleanQuit, preferences.screenMode == .agentsScreen {
                preferences.screenMode = .displayOff
                notifier.post("Agents-screen mode turned off",
                              "The last closed-lid session ended unexpectedly. Turn the mode back on in Settings.")
            }
            screen.processPendingRestore(lidOpen: !monitor.lid.isClosed)
        }
        // A mode saved before the lock was verified is not honoured.
        if preferences.screenMode == .agentsScreen, !preferences.lockVerified {
            preferences.screenMode = .displayOff
            log.log("agents-screen mode was saved without a verified lock; using display off")
        }
    }

    /// Entry point for App Intents: the same path as the menu and the hotkey (refresh, then the
    /// controller). Returns the state before the event, or nil while launch has not finished.
    func dispatch(_ event: SessionEvent) -> SessionState? {
        guard !terminating, let controller, let onEvent = monitor?.onEvent else { return nil }
        let before = controller.state
        onEvent(event)
        return before
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Launch failed before the controller existed: nothing to clean up.
        guard controller != nil else { return .terminateNow }
        if terminating { return .terminateLater }
        terminating = true
        log.log("quit requested")
        assertions.setTransitionGuard(true)

        var finished = false
        let finish: () -> Void = { [self] in
            if finished { return }
            finished = true
            // On this path the flag is cleared last: with the lid shut the Mac sleeps as soon as it
            // clears. (On the signal path the C handler has already made an immediate best-effort
            // clear before handing off to this quit; that is by design.)
            // `shutdown` also stops the controller taking events, so nothing queued behind
            // this block can re-arm. The transition guard stays held until the process exits.
            let cleared = controller.shutdown()
            log.log("quit: flag clear \(cleared ? "ok" : "FAILED")")
            if cleared {
                noteRecordLeftByCleanQuit()
                pidFile.remove()
            }
            signals.terminationFinished()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        // Lock and restore first when someone could see the screen. With the lid shut
        // the record stays on disk for the next launch.
        // `finish` is dispatched, never called inline: AppKit ignores a reply sent
        // before this method has returned `.terminateLater`.
        screen.processPendingRestore(lidOpen: !monitor.lid.isClosed) {
            DispatchQueue.main.async(execute: finish)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: finish)
        return .terminateLater
    }

    /// Tells the next launch that a leftover record is not evidence of a crash.
    private func noteRecordLeftByCleanQuit() {
        if store?.exists == true {
            UserDefaults.standard.set(true, forKey: Self.cleanQuitLeftRestoreKey)
            UserDefaults.standard.synchronize()
        }
    }

    /// Report a fatal launch problem and exit. Shows an alert only when someone can see it.
    private func failLaunch(_ message: String) -> Never {
        log?.log("launch failed: \(message)")
        notifier.post("Clam could not start", message)
        if monitor?.lid.isClosed == false {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Clam could not start"
            alert.informativeText = message
            alert.runModal()
        } else {
            // No alert with the lid shut. Posting is asynchronous; give it time to leave the process.
            Thread.sleep(forTimeInterval: 1)
        }
        exit(1)
    }
}
