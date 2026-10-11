import ClamCore
import Foundation

enum LidSound: String, CaseIterable {
    case off, chime, latch, shell
}

/// Typed access to UserDefaults.
final class Preferences {
    private enum Key {
        static let screenMode = "screenMode"
        static let lockVerified = "lockVerified"
        static let batterySafetyEnabled = "batterySafetyEnabled"
        static let batteryThreshold = "batteryThreshold"
        static let rightClickToggles = "rightClickToggles"
        static let tiltGestureEnabled = "tiltGestureEnabled"
        static let pauseNoticeEnabled = "pauseNoticeEnabled"
        static let lidSound = "lidSound"
        static let hotkey = "hotkey"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.batterySafetyEnabled: true,
            Key.batteryThreshold: 20,
            Key.rightClickToggles: true,
            Key.tiltGestureEnabled: true,
            Key.pauseNoticeEnabled: true,
        ])
    }

    var screenMode: ScreenMode {
        get { ScreenMode(rawValue: defaults.string(forKey: Key.screenMode) ?? "") ?? .displayOff }
        set { defaults.set(newValue.rawValue, forKey: Key.screenMode) }
    }

    /// Clam has locked this Mac once and seen the lock take. Agents-screen mode needs it.
    var lockVerified: Bool {
        get { defaults.bool(forKey: Key.lockVerified) }
        set { defaults.set(newValue, forKey: Key.lockVerified) }
    }

    /// The saved mode, with agents-screen counted only once the lock is verified.
    var usableScreenMode: ScreenMode {
        screenMode == .agentsScreen && !lockVerified ? .displayOff : screenMode
    }

    var batterySafetyEnabled: Bool {
        get { defaults.bool(forKey: Key.batterySafetyEnabled) }
        set { defaults.set(newValue, forKey: Key.batterySafetyEnabled) }
    }

    var batteryThreshold: Int {
        get { SafetySettings(batteryThreshold: defaults.integer(forKey: Key.batteryThreshold)).batteryThreshold }
        set { defaults.set(newValue, forKey: Key.batteryThreshold) }
    }

    var rightClickToggles: Bool {
        get { defaults.bool(forKey: Key.rightClickToggles) }
        set { defaults.set(newValue, forKey: Key.rightClickToggles) }
    }

    var tiltGestureEnabled: Bool {
        get { defaults.bool(forKey: Key.tiltGestureEnabled) }
        set { defaults.set(newValue, forKey: Key.tiltGestureEnabled) }
    }

    var pauseNoticeEnabled: Bool {
        get { defaults.bool(forKey: Key.pauseNoticeEnabled) }
        set { defaults.set(newValue, forKey: Key.pauseNoticeEnabled) }
    }

    var lidSound: LidSound {
        get { LidSound(rawValue: defaults.string(forKey: Key.lidSound) ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Key.lidSound) }
    }

    var hotkey: HotkeyBinding? {
        get {
            guard let data = defaults.data(forKey: Key.hotkey) else { return nil }
            return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.hotkey)
            } else {
                defaults.removeObject(forKey: Key.hotkey)
            }
        }
    }

    var sessionSettings: SessionSettings {
        SessionSettings(screenMode: screenMode,
                        safety: SafetySettings(batterySafetyEnabled: batterySafetyEnabled,
                                               batteryThreshold: batteryThreshold))
    }
}
