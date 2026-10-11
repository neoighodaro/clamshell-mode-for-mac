import ClamCore
import Foundation

// Read-only diagnostics. No subcommand here may set the lid-sleep flag.
let command = CommandLine.arguments.dropFirst().first ?? "help"

switch command {
case "flag-open":
    print(SleepFlag() != nil ? "root-domain connection: ok" : "root-domain connection: FAILED")
case "lid":
    let lid = LidObserver()
    print("supported: \(lid.isSupported) closed: \(lid.isClosed) last sleep reason: \(lid.lastSleepReason() ?? "none")")
case "power":
    let sample = PowerSource().sample()
    let thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
    print("on battery: \(sample.onBattery) percent: \(sample.percent.map(String.init) ?? "unreadable") thermal: \(thermal)")
case "watch-lid":
    let lid = LidObserver()
    lid.onChange = { print($0 ? "lid closed" : "lid opened") }
    lid.start()
    print("watching the lid for 60 seconds; half-close and reopen it")
    RunLoop.main.run(until: Date().addingTimeInterval(60))
case "angle":
    let sensor = LidAngleSensor()
    print("available: \(sensor.isAvailable) angle: \(sensor.angle().map(String.init) ?? "unreadable")")
case "displays":
    let topology = DisplayTopology()
    for d in topology.list() ?? [] {
        print("id \(d.id) builtin \(d.isBuiltin) vendor 0x\(String(d.vendor, radix: 16)) model 0x\(String(d.model, radix: 16)) serial \(d.serial)")
    }
    print(topology.snapshot().map { "builtin: \($0.builtin.map(String.init) ?? "none") external: \($0.hasExternal)" } ?? "unreadable")
case "brightness":
    let topology = DisplayTopology()
    _ = topology.snapshot()
    let control = BrightnessControl(display: { topology.lastBuiltin })
    print("available: \(control.isAvailable) brightness: \(control.get().map { String($0) } ?? "unreadable")")
case "locked":
    print("session locked: \(SessionLocker().isLocked)")
default:
    print("usage: clam-probe <flag-open|lid|power|watch-lid|angle|displays|brightness|locked>")
}
