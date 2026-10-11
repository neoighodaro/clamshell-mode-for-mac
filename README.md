# Clam

A macOS menu bar app that keeps your Mac awake with the lid closed.

Arm it from the menu bar icon, a global hotkey, a Shortcuts action, or by holding Option while closing the lid (arms for one close). While the lid is closed, Clam can either turn the display off or keep it on at zero brightness so screen capture keeps working for agents.

It disarms on its own when the battery runs low or the Mac runs hot, and a small watchdog process restores normal sleep if the app ever dies while armed.

## Building

Requires macOS 14 or later and Xcode 16 or later.

Open `Clam.xcodeproj` and run the `Clam` scheme, or build from the command line:

```sh
xcodebuild -project Clam.xcodeproj -scheme Clam build
```

Run the tests for the core package:

```sh
swift test --package-path ClamCore
```

To sign builds, copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your team ID. That file is not checked in.

`scripts/build-release.sh <team-id>` builds a Developer ID signed release build and prints the path to `Clam.app`. It needs that team's Developer ID certificate. Without the argument it uses `Config/Local.xcconfig`, or asks.

## Layout

- `App/`: the menu bar app
- `ClamCore/`: Swift package with the session logic, hardware access and tests
- `Watchdog/`: the helper that cleans up if the app dies while armed

## License

MIT. See [LICENSE](LICENSE).
