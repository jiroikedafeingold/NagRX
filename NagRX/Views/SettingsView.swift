import SwiftUI

struct SettingsView: View {
    @State private var testScheduled = false
    @State private var reNagInterval = AppSettings.shared.reNagIntervalMinutes
    @State private var defaultSound = AppSettings.shared.defaultSound
    @State private var celebrationEnabled = AppSettings.shared.celebrationEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder Interval") {
                    VStack(alignment: .leading) {
                        Text("Re-alert every **\(reNagInterval) minute\(reNagInterval == 1 ? "" : "s")**")
                        Slider(
                            value: Binding(
                                get: { Double(reNagInterval) },
                                set: {
                                    reNagInterval = Int($0)
                                    AppSettings.shared.reNagIntervalMinutes = reNagInterval
                                }
                            ),
                            in: 1...10,
                            step: 1
                        )
                    }
                    Text("If you don't respond, the alarm will keep firing at this interval.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Default Alert Sound") {
                    ForEach(NagRXSound.allCases) { sound in
                        SoundRow(
                            sound: sound,
                            isSelected: sound == defaultSound,
                            onSelect: {
                                defaultSound = sound
                                AppSettings.shared.defaultSound = sound
                            }
                        )
                    }
                }

                Section("Celebration") {
                    Toggle("Show celebration animation", isOn: Binding(
                        get: { celebrationEnabled },
                        set: {
                            celebrationEnabled = $0
                            AppSettings.shared.celebrationEnabled = $0
                        }
                    ))
                    Text("Plays a confetti animation when you mark a medication as taken. Haptics still fire either way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Test") {
                    Button {
                        scheduleTestAlarm()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text(testScheduled ? "Test alarm in 5 seconds..." : "Fire Test Alarm")
                        }
                    }
                    .disabled(testScheduled)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("NagRX will keep alerting you with audio and vibration until you acknowledge each medication reminder. Snooze delays the alert for 15 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func scheduleTestAlarm() {
        testScheduled = true
        let testDate = Date().addingTimeInterval(5)
        let sound = defaultSound
        Task {
            await NotificationService.shared.scheduleAlarm(
                identifier: "nagrx_test_\(UUID().uuidString)",
                medicationName: "Test Medication",
                fireDate: testDate,
                sound: sound
            )
            AlarmPlayer.shared.setSchedule([
                AlarmPlayer.Entry(
                    identifier: "nagrx_test",
                    fireDates: [testDate],
                    sound: sound
                )
            ])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            testScheduled = false
        }
    }
}
