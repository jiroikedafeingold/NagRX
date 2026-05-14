import AVFoundation

/// Simple wrapper for previewing alarm sounds in the settings UI.
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var player: AVAudioPlayer?

    private init() {}

    func play(_ sound: NagRXSound) {
        stop()

        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: NagRXSound.fileExtension) else {
            print("[NagRX] SoundPlayer: file not found: \(sound.fileName).\(NagRXSound.fileExtension)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
        } catch {
            print("[NagRX] SoundPlayer error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    var isPlaying: Bool {
        player?.isPlaying == true
    }
}
