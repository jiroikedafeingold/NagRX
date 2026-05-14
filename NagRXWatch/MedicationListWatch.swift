import SwiftUI

struct MedicationListWatch: View {
    private var store = WatchDataStore.shared

    private var sortedMedications: [WatchMedication] {
        store.medications.sorted { a, b in
            if a.isEnabled != b.isEnabled { return a.isEnabled }
            return a.nextFireDate < b.nextFireDate
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.medications.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "pills")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Medications")
                            .font(.headline)
                        Text("Add medications on your iPhone to see them here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(sortedMedications) { med in
                            WatchMedicationRow(medication: med)
                        }

                        if let syncDate = store.lastSyncDate {
                            Section {
                                Text("Synced \(syncDate, style: .relative) ago")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("NagRX")
        }
    }
}

// MARK: - WatchMedicationRow

private struct WatchMedicationRow: View {
    let medication: WatchMedication

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(medication.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if !medication.isEnabled {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(medication.formattedSchedule)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .opacity(medication.isEnabled ? 1.0 : 0.5)
    }
}
