import AVFoundation

/// Plays a looping silent audio stream to keep the app process alive in the background.
///
/// As long as an AVAudioSession with category .playback is active, iOS will not
/// suspend the app, which lets AlarmPlayer's timer fire at the correct time even
/// when the device is locked and the ringer switch is off.
final class BackgroundAudioKeepAlive {
    static let shared = BackgroundAudioKeepAlive()

    private var player: AVAudioPlayer?
    private var healthTimer: Timer?
    private(set) var isRunning = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    func start() {
        configureSession()

        if isRunning, player?.isPlaying == true {
            startHealthTimer()
            return
        }

        guard let url = Bundle.main.url(forResource: NagRXSound.pebble.fileName, withExtension: NagRXSound.fileExtension) else {
            print("[NagRX] BackgroundAudioKeepAlive: sound file not found")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 0          // inaudible
            player?.numberOfLoops = -1  // loop forever
            player?.play()
            isRunning = true
            startHealthTimer()
        } catch {
            print("[NagRX] BackgroundAudioKeepAlive error: \(error)")
        }
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        player?.stop()
        player = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Session configuration

    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Re-applying the category forces the system to re-evaluate the audio
            // route, so only do it when the session isn't already set up.
            if session.category != .playback
                || !session.categoryOptions.contains(.mixWithOthers) {
                try session.setCategory(
                    .playback,
                    options: [.mixWithOthers]
                )
            }
            // The keep-alive stream plays around the clock, so the audio render
            // callback rate is a standing battery cost. Requesting the longest
            // buffer iOS offers (~93 ms, the documented maximum) cuts those
            // callbacks roughly fourfold. The only tradeoff is output latency,
            // which is irrelevant for an alarm.
            if session.preferredIOBufferDuration < 0.09 {
                try session.setPreferredIOBufferDuration(0.093)
            }
            try session.setActive(true)
        } catch {
            print("[NagRX] BackgroundAudioKeepAlive session error: \(error)")
        }
    }

    // MARK: - Health check

    /// Backstop interval. The interruption, route-change and media-reset
    /// observers already catch every known failure mode the instant it happens,
    /// so this timer only guards against the unknown ones and can run rarely.
    private static let healthCheckInterval: TimeInterval = 120

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let t = Timer(timeInterval: Self.healthCheckInterval, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        // A wide tolerance lets iOS coalesce this with other scheduled work
        // instead of booking a dedicated CPU wakeup every time.
        t.tolerance = Self.healthCheckInterval / 4
        RunLoop.main.add(t, forMode: .common)
        healthTimer = t
    }

    private func checkHealth() {
        guard isRunning else { return }
        if player == nil || player?.isPlaying == false {
            print("[NagRX] BackgroundAudioKeepAlive: player stopped, restarting")
            isRunning = false
            start()
        }
    }

    // MARK: - Interruption handling

    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        if type == .ended {
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if options.contains(.shouldResume) || self.isRunning {
                    self.configureSession()
                    self.player?.play()
                }
            }
        }
    }

    @objc nonisolated private func handleRouteChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isRunning, self.player?.isPlaying == false {
                self.configureSession()
                self.player?.play()
            }
        }
    }

    @objc nonisolated private func handleMediaReset() {
        print("[NagRX] BackgroundAudioKeepAlive: media services reset, restarting")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.player = nil
            self.isRunning = false
            self.start()
        }
    }
}
