import AppKit

final class LidSoundPlayer {
    private var current: NSSound?

    func play(_ sound: LidSound) {
        guard sound != .off,
              let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else { return }
        current = NSSound(contentsOf: url, byReference: true)
        current?.play()
    }
}
