import AppKit
import ClamCore

/// Watches the hardware and the workspace, keeps an `Environment` snapshot current,
/// and turns changes into `SessionEvent`s. Main-thread only.
final class EnvironmentMonitor {
    static let rivalBundleID = "com.rathonyi.clamshell"

    let lid = LidObserver()
    let power = PowerSource()
    let displays = DisplayTopology()
    private(set) var current = ClamCore.Environment.nominal
    var onEvent: ((SessionEvent) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var runningAppsObservation: NSKeyValueObservation?
    private var rival = RivalTracker()
    /// Taken only on a power-source event or the 30 second timer. `refresh()` runs far
    /// more often, and "unreadable twice in a row" must mean two samples apart in time.
    private var powerSample: PowerSample

    init() {
        powerSample = power.sample()
        refresh()
    }

    static var rivalIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rivalBundleID).isEmpty
    }

    /// Re-reads everything. Also the one place a Clamshell launch is detected, so the launch
    /// notification, the running-applications observation, the 30 second timer and every arm
    /// all catch it, and it is reported once.
    func refresh() {
        let sample = powerSample
        let snapshot = displays.snapshot()
        let rivalRunning = Self.rivalIsRunning
        current = ClamCore.Environment(
            lidClosed: lid.isClosed,
            externalDisplay: snapshot?.hasExternal,
            onBattery: sample.onBattery,
            batteryPercent: sample.percent,
            batteryMissingSamples: power.missingSamples,
            thermal: ThermalLevel(ProcessInfo.processInfo.thermalState),
            rivalRunning: rivalRunning)
        if rival.update(running: rivalRunning) { onEvent?(.rivalLaunched) }
    }

    func start() {
        lid.onChange = { [weak self] closed in
            self?.refresh()
            self?.onEvent?(closed ? .lidClosed : .lidOpened)
        }
        lid.start()

        power.onChange = { [weak self] in
            self?.samplePower()
            self?.refresh()
            self?.onEvent?(.reapplyTrigger)
            self?.onEvent?(.environmentChanged)
        }
        power.start()

        displays.onChange = { [weak self] in self?.environmentChanged() }
        displays.start()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.onEvent?(.systemWillSleep)
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.lid.refresh()
            self?.refresh()
            self?.onEvent?(.systemDidWake)
            self?.onEvent?(.environmentChanged)
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] _ in
            self?.onEvent?(.reapplyTrigger)
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] _ in
            self?.onEvent?(.reapplyTrigger)
        }
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] _ in
            self?.refresh()
        }
        // The launch notification is not posted for menu-bar (LSUIElement) apps, which is what
        // Clamshell is. The running-applications list does change for them.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] _ in
            self?.refresh()
        }
        observe(NotificationCenter.default, ProcessInfo.thermalStateDidChangeNotification) { [weak self] _ in
            self?.environmentChanged()
        }

        // Catches anything the notifications miss, and feeds the battery-unreadable counter.
        // Common modes, so it keeps firing while a status menu is open.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.samplePower()
            self?.lid.refresh()
            self?.environmentChanged()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func samplePower() {
        powerSample = power.sample()
    }

    private func environmentChanged() {
        refresh()
        onEvent?(.environmentChanged)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping (Notification) -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: handler))
    }
}
