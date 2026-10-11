import AppKit
import ClamCore

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}

final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: SessionController
    private let preferences: Preferences

    /// False when the watchdog is not registered and running.
    var relaunchProtected = true { didSet { refresh() } }
    var onOpenSettings: (() -> Void)?
    /// Called before an arm-type event so the safety checks see a fresh environment.
    var refreshEnvironment: (() -> Void)?
    /// Spike actions, shown only when the `debugMenu` default is set.
    var debugItems: [(title: String, action: () -> Void)] = []

    private func send(_ event: SessionEvent) {
        if event == .arm || event == .toggle { refreshEnvironment?() }
        controller.handle(event)
    }

    init(controller: SessionController, preferences: Preferences) {
        self.controller = controller
        self.preferences = preferences
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()
    }

    func refresh() {
        let symbol: String
        if controller.clearPending {
            symbol = "exclamationmark.triangle"
        } else {
            switch controller.state {
            case .disarmed: symbol = "laptopcomputer"
            case .armed, .closed: symbol = "lock.laptopcomputer"
            case .paused: symbol = "pause.circle"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusText)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.title = image == nil ? "Clam" : ""
        item.button?.toolTip = "Clam: \(statusText)"
    }

    private var statusText: String {
        if controller.clearPending { return "Could not restore lid sleep; retrying" }
        switch controller.state {
        case .disarmed: return "Disarmed. Closing the lid sleeps your Mac."
        case .armed(.persistent): return "Armed. Your Mac stays awake when the lid closes."
        case .armed(.oneClose): return "Armed for the next lid close."
        case .closed: return "Running with the lid closed."
        case .paused: return "Paused while an external display is connected."
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if secondary, preferences.rightClickToggles {
            send(.toggle)
        } else {
            showMenu()
        }
    }

    private func showMenu() {
        // Assigning the menu only for this click keeps right-click free for toggling.
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if !relaunchProtected {
            let warning = NSMenuItem(title: "No relaunch protection (see Settings)", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(.separator())

        if controller.state == .disarmed {
            menu.addItem(ActionItem("Arm") { [weak self] in self?.send(.arm) })
        } else {
            menu.addItem(ActionItem("Disarm") { [controller] in controller.handle(.disarm) })
        }
        if controller.clearPending {
            menu.addItem(ActionItem("Retry Restoring Lid Sleep") { [controller] in controller.retryClear() })
        }
        menu.addItem(.separator())
        if preferences.defaults.bool(forKey: "debugMenu") {
            for entry in debugItems {
                menu.addItem(ActionItem("Debug: \(entry.title)", handler: entry.action))
            }
            menu.addItem(.separator())
        }
        menu.addItem(ActionItem("Settings…") { [weak self] in self?.onOpenSettings?() })
        menu.addItem(ActionItem("Quit Clam") { NSApp.terminate(nil) })
        return menu
    }
}
