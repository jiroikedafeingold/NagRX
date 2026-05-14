import SwiftUI
import SwiftData

struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var medication: Medication

    @State private var name: String
    @State private var scheduleTime: Date
    @State private var selectedSound: NagRXSound
    @State private var isEnabled: Bool
    @State private var frequency: ScheduleFrequency
    @State private var selectedWeekdays: Set<Int>
    @State private var monthlyDay: Int
    @State private var biweeklyStartsThisWeek: Bool
    @State private var silentReminder: Bool
    @State private var showDeleteConfirmation = false

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty ||
        (frequency == .weekly && selectedWeekdays.isEmpty)
    }

    init(medication: Medication) {
        self.medication = medication
        _name = State(initialValue: medication.name)
        _selectedSound = State(initialValue: medication.sound)
        _isEnabled = State(initialValue: medication.isEnabled)
        _frequency = State(initialValue: medication.frequency)
        _selectedWeekdays = State(initialValue: medication.selectedWeekdays)
        _monthlyDay = State(initialValue: medication.monthlyDay)
        _biweeklyStartsThisWeek = State(initialValue: medication.isOnWeek(for: Date()))
        _silentReminder = State(initialValue: medication.silentReminder)

        // Build a date from hour/minute for the picker
        var comps = DateComponents()
        comps.hour = medication.scheduledHour
        comps.minute = medication.scheduledMinute
        let date = Calendar.current.date(from: comps) ?? Date()
        _scheduleTime = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Medication name", text: $name)
                    Toggle("Enabled", isOn: $isEnabled)
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

                Section {
                    Button("Delete Medication", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Edit Medication")
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
                        saveChanges()
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .confirmationDialog(
                "Delete \(medication.name)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteMedication()
                }
            } message: {
                Text("This will remove the medication and all its alarms.")
            }
        }
    }

    private func saveChanges() {
        SoundPlayer.shared.stop()

        let cal = Calendar.current
        let hour = cal.component(.hour, from: scheduleTime)
        let minute = cal.component(.minute, from: scheduleTime)

        medication.name = name.trimmingCharacters(in: .whitespaces)
        medication.scheduledHour = hour
        medication.scheduledMinute = minute
        medication.selectedSound = selectedSound.rawValue
        medication.isEnabled = isEnabled
        medication.frequency = frequency
        medication.selectedWeekdays = selectedWeekdays
        medication.monthlyDay = monthlyDay
        medication.silentReminder = silentReminder

        if frequency == .everyOtherWeek {
            let cal = Calendar.current
            let monday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            if var thisMonday = cal.date(from: monday) {
                if !biweeklyStartsThisWeek {
                    thisMonday = cal.date(byAdding: .weekOfYear, value: 1, to: thisMonday)!
                }
                medication.biweeklyStartTimestamp = thisMonday.timeIntervalSince1970
            }
        }

        try? modelContext.save()

        Task { @MainActor in
            await NagScheduler.shared.sync()
        }

        dismiss()
    }

    private func deleteMedication() {
        SoundPlayer.shared.stop()
        NagScheduler.shared.cancelMedication(medication)
        modelContext.delete(medication)
        try? modelContext.save()

        Task { @MainActor in
            await NagScheduler.shared.sync()
        }

        dismiss()
    }
}
