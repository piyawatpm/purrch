import AVFoundation

/// The generated sounds (see tools/soundgen.py). Players are cached so a click
/// never blocks on disk, and replaying a cue restarts it rather than stacking
/// two copies on top of each other.
final class Sounds {
    static let shared = Sounds()

    enum Cue: String {
        case meow, crunch

        /// Per-cue balance, before the user's master volume is applied.
        var baseVolume: Float {
            switch self {
            case .meow:   return 0.55
            case .crunch: return 0.5
            }
        }
    }

    private var players: [Cue: AVAudioPlayer] = [:]

    private init() {
        for cue in [Cue.meow, Cue.crunch] {
            guard let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "wav",
                                              subdirectory: "Resources/Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[cue] = player
        }
    }

    func play(_ cue: Cue) {
        let settings = Settings.shared
        guard settings.soundEnabled, let player = players[cue] else { return }
        // Read the volume per play, so the slider takes effect straight away.
        player.volume = cue.baseVolume * Float(settings.volume)
        player.stop()
        player.currentTime = 0
        player.play()
    }
}
