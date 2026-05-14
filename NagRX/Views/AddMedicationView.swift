import SwiftUI
import SwiftData

struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var scheduleTime = Date()
    @State private var selectedSound: NagRXSound = AppSettings.shared.defaultSound
    @State private var silentReminder: Bool = false
    @State private var frequency: ScheduleFrequency = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var monthlyDay: Int = 1
    @State private var biweeklyStartsThisWeek: Bool = true

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty ||
        (frequency == .weekly && selectedWeekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Medication name", text: $name)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(ScheduleFrequency.allCases) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    DatePicker(
                        "Time",
                        selection: $scheduleTime,
                        displayedComponents: .hourAndMinute
                    )

                    if frequency == .everyOtherWeek {
                        Picker("Starting Week", selection: $biweeklyStartsThisWeek) {
                            Text("This week").tag(true)
                            Text("Next week").tag(false)
                        }
                    }

                    if frequency == .weekly {
                        WeekdayPicker(selectedWeekdays: $selectedWeekdays)
                    }

                    if frequency == .monthly {
                        MonthlyDayPicker(monthlyDay: $monthlyDay)
                    }
                }

                Section {
                    Toggle("Silent Reminder", isOn: $silentReminder)
                } header: {
                    Text("Alert Type")
                } footer: {
                    if silentReminder {
                        Text("You'll get a notification but no audible alarm or repeated nagging.")
                    }
                }

                if !silentReminder {
                    Section("Alert Sound") {
                        ForEach(NagRXSound.allCases) { sound in
                            SoundRow(
                                sound: sound,
                                isSelected: sound == selectedSound,
                                onSelect: { selectedSound = sound }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        SoundPlayer.shared.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMedication()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func saveMedication() {
        SoundPlayer.shared.stop()

        let cal = Calendar.current
        let hour = cal.component(.hour, from: scheduleTime)
        let minute = cal.component(.minute, from: scheduleTime)

        var bitmask = 0
        for day in selectedWeekdays {
            bitmask |= (1 << (day - 1))
        }

        // Compute biweekly start: Monday of this week or next week
        var biweeklyStart: TimeInterval = 0
        if frequency == .everyOtherWeek {
            let monday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            if var thisMonday = cal.date(from: monday) {
                if !biweeklyStartsThisWeek {
                    thisMonday = cal.date(byAdding: .weekOfYear, value: 1, to: thisMonday)!
                }
                biweeklyStart = thisMonday.timeIntervalSince1970
            }
        }

        let medication = Medication(
            name: name.trimmingCharacters(in: .whitespaces),
            scheduledHour: hour,
            scheduledMinute: minute,
            selectedSound: selectedSound.rawValue,
            frequency: frequency,
            weeklyDaysBitmask: bitmask,
            monthlyDay: monthlyDay,
            biweeklyStartTimestamp: biweeklyStart,
            silentReminder: silentReminder
        )

        modelContext.insert(medication)
        try? modelContext.save()

        Task { @MainActor in
            await NagScheduler.shared.sync()
        }

        dismiss()
    }
}
