import AVFoundation
import Foundation

/// Fires alarm audio at scheduled times, bypassing the silent switch.
///
/// Works alongside UNUserNotificationCenter: notifications provide the visual popup
/// and Snooze/Dismiss actions; AlarmPlayer provides the audio that ignores silent mode.
///
/// Requires the app to have an active AVAudioSession (.playback) so it can run
/// while backgrounded — BackgroundAudioKeepAlive handles that.
final class AlarmPlayer {
    static let shared = AlarmPlayer()

    // MARK: - Types

    struct Entry: Codable {
        let identifier: String
        let fireDates: [Date]
        let sound: NagRXSound
        var medicationName: String = ""
    }

    // MARK: - Persistence

    private static let storageKey = "AlarmPlayerEntries"

    private func persistEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }

        let now = Date()
        return saved.compactMap { entry in
            let futureDates = entry.fireDates.filter { $0 > now }
            guard !futureDates.isEmpty else { return nil }
            return Entry(identifier: entry.identifier, fireDates: futureDates, sound: entry.sound)
        }
    }

    // MARK: - State

    private var entries: [Entry] = []
    private var firedTimestamps: Set<Int> = []
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?
    var isPlaying: Bool { player?.isPlaying == true }

    private init() {
        entries = Self.loadEntries()
        if !entries.isEmpty {
            print("[NagRX] AlarmPlayer restored \(entries.count) entries from disk")
            startTimerIfNeeded()
        }
    }

    // MARK: - Public API

    /// Replace the full alarm schedule. Called after every sync().
    func setSchedule(_ newEntries: [Entry]) {
        entries = newEntries
        pruneOldTimestamps()
        persistEntries()
        startTimerIfNeeded()
    }

    /// Add a snooze entry (called when user snoozes a notification).
    func addSnooze(identifier: String, at fireDate: Date, sound: NagRXSound, medicationName: String = "") {
        let snoozeID = identifier + "_snooze"
        entries.removeAll { $0.identifier == snoozeID }
        entries.append(Entry(identifier: snoozeID, fireDates: [fireDate], sound: sound, medicationName: medicationName))
        persistEntries()
        startTimerIfNeeded()
    }

    /// Stop current playback and remove all entries for this alarm.
    func dismiss(identifier: String) {
        stopPlayback()
        NotificationService.shared.stopHaptics()
        entries.removeAll {
            $0.identifier == identifier || $0.identifier.hasPrefix(identifier)
        }
        persistEntries()
    }

    /// Stop current playback (the snooze notification will re-fire later).
    func stopForSnooze(identifier: String) {
        stopPlayback()
        NotificationService.shared.stopHaptics()
        // Keep only the snooze entry
        entries.removeAll {
            $0.identifier != identifier + "_snooze" &&
            ($0.identifier == identifier || $0.identifier.hasPrefix(identifier + "_r"))
        }
        persistEntries()
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        var justFiredNames: [String] = []

        for entry in entries {
            for fireDate in entry.fireDates {
                let age = now.timeIntervalSince(fireDate)
                guard age >= 0, age < 5 else { continue }

                let stamp = Int(fireDate.timeIntervalSince1970)
                guard !firedTimestamps.contains(stamp) else { continue }

                firedTimestamps.insert(stamp)
                playSound(entry.sound)
                NotificationService.shared.startRepeatingHaptics()

                if !entry.medicationName.isEmpty {
                    justFiredNames.append(entry.medicationName)
                }
            }
        }

        // Update widget shared state when alarms fire
        if !justFiredNames.isEmpty {
            var active = SharedState.activeMedicationNames
            for name in justFiredNames where !active.contains(name) {
                active.append(name)
            }
            SharedState.activeMedicationNames = active
            SharedState.hasActiveAlarm = true
        }

        stopTimerIfIdle()
    }

    private func stopTimerIfIdle() {
        let now = Date()
        let hasUpcoming = entries.contains { entry in
            entry.fireDates.contains { $0 > now }
        }
        if !hasUpcoming && !isPlaying {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Playback

    /// Called externally (e.g. from NotificationService.willPresent) when the
    /// timer-based path hasn't triggered yet but a notification just arrived.
    func playSoundDirectly(_ sound: NagRXSound) {
        playSound(sound)
    }

    private func playSound(_ sound: NagRXSound) {
        stopPlayback()

        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: NagRXSound.fileExtension) else {
            print("[NagRX] AlarmPlayer: sound file not found: \(sound.fileName).\(NagRXSound.fileExtension)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
        } catch {
            print("[NagRX] AlarmPlayer playback error: \(error)")
            return
        }

        // Auto-stop after 60 seconds if the user takes no action
        let work = DispatchWorkItem { [weak self] in
            self?.stopPlayback()
            NotificationService.shared.stopHaptics()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    func stopPlayback() {
        stopWork?.cancel()
        stopWork = nil
        player?.stop()
        player = nil
    }

    // MARK: - Helpers

    private func pruneOldTimestamps() {
        let cutoff = Int(Date().timeIntervalSince1970) - 600
        firedTimestamps = firedTimestamps.filter { $0 > cutoff }
    }
}
