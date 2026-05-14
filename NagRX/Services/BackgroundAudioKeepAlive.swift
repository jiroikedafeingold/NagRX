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
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[NagRX] BackgroundAudioKeepAlive session error: \(error)")
        }
    }

    // MARK: - Health check

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
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
