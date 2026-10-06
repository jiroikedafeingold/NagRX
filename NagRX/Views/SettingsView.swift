import SwiftUI

struct SettingsView: View {
    @State private var testScheduled = false
    @State private var reNagInterval = AppSettings.shared.reNagIntervalMinutes
    @State private var defaultSound = AppSettings.shared.defaultSound
    @State private var celebrationEnabled = AppSettings.shared.celebrationEnabled
    @State private var alarmsAllowed = DoseAlarms.shared.isAuthorized
    @State private var alarmsDenied = DoseAlarms.shared.isDenied
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    alarmPermissionRow
                } header: {
                    Text("Alarms")
                } footer: {
                    Text("NagRX rings a real alarm for each dose, so it sounds even when your iPhone is on silent or in a Focus, and works even if NagRX isn't open. If alarms aren't allowed, you get notifications instead, which follow your ringer switch.")
                }

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
                            step: 1,
                            onEditingChanged: { editing in
                                // Re-alert times are baked into the scheduled alarms.
                                if !editing { Task { await NagScheduler.shared.sync() } }
                            }
                        )
                    }
                    Text("If you don't take it, the alarm keeps ringing again at this interval.")
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
                    Toggle("Celebrate when taken", isOn: Binding(
                        get: { celebrationEnabled },
                        set: {
                            celebrationEnabled = $0
                            AppSettings.shared.celebrationEnabled = $0
                            // Re-register so the "I Took It" notification action picks up
                            // (or drops) its .foreground option immediately.
                            NotificationService.shared.registerCategories()
                        }
                    ))
                    Text("Plays a confetti animation and success haptics when you mark a medication as taken. When on, tapping \"I Took It\" briefly opens the app so the haptics and animation can fire.")
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
                    Text("NagRX keeps ringing until you confirm each dose. Tap Stop on the alarm when you've taken it; Snooze rings again in 15 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: scenePhase) { _, phase in
                // Picks up a change made in iOS Settings while NagRX was away.
                if phase == .active { refreshAlarmState() }
            }
            .onAppear { refreshAlarmState() }
        }
    }

    /// Re-reads the alarm permission; it can change at launch or in iOS Settings.
    private func refreshAlarmState() {
        alarmsAllowed = DoseAlarms.shared.isAuthorized
        alarmsDenied = DoseAlarms.shared.isDenied
    }

    /// Shows whether NagRX may schedule system alarms, with a way to fix it.
    @ViewBuilder
    private var alarmPermissionRow: some View {
        if alarmsAllowed {
            Label("Alarms Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if alarmsDenied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Alarms Are Off — Open Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Button {
                Task {
                    await DoseAlarms.shared.requestAuthorization()
                    refreshAlarmState()
                    await NagScheduler.shared.sync()
                }
            } label: {
                Label("Allow Alarms", systemImage: "alarm")
            }
        }
    }

    private func scheduleTestAlarm() {
        testScheduled = true
        let sound = defaultSound
        Task {
            if DoseAlarms.shared.isAuthorized {
                _ = await DoseAlarms.shared.scheduleTest(sound: sound)
            } else {
                await NotificationService.shared.scheduleAlarm(
                    identifier: "nagrx_test_\(UUID().uuidString)",
                    medicationName: "Test Medication",
                    fireDate: Date().addingTimeInterval(5),
                    sound: sound,
                    reNagCount: 0
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            testScheduled = false
        }
    }
}
