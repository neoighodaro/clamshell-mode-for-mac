<div align="center">

<img src=".github/icon.png" width="128" alt="Clam icon">

# Clam

**Keep your Mac awake with the lid closed.**

A small menu bar app for macOS.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-1f1f21)
![Swift 5](https://img.shields.io/badge/Swift-5-f0a93b)
[![MIT License](https://img.shields.io/badge/license-MIT-f3ebe1)](LICENSE)

</div>

## What it does

Close the lid and your Mac keeps running instead of going to sleep.

| | |
| --- | --- |
| **Arm it your way** | From the menu bar icon, a global hotkey, or a Shortcuts action. |
| **One-close gesture** | Hold Option while closing the lid to arm for just that one close. |
| **Screen modes** | Turn the display off, or keep it on at zero brightness so screen capture keeps working for agents. |
| **Safety** | Disarms on its own when the battery runs low or the Mac runs hot. |
| **Watchdog** | A small helper restores normal sleep if the app ever dies while armed. |

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

### Signing

Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your team ID. That file is not checked in.

### Release builds

```sh
scripts/build-release.sh <team-id>
```

Builds a Developer ID signed release build and prints the path to `Clam.app`. It needs that team's Developer ID certificate. Without the argument it uses `Config/Local.xcconfig`, or asks.

## Layout

| Path | Contents |
| --- | --- |
| `App/` | The menu bar app |
| `ClamCore/` | Swift package with the session logic, hardware access and tests |
| `Watchdog/` | The helper that cleans up if the app dies while armed |

## License

MIT. See [LICENSE](LICENSE).
