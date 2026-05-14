import SwiftUI

struct MedicationRow: View {
    let medication: Medication

    private var dimmed: Bool { !medication.isEnabled }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.headline)
                    .foregroundStyle(dimmed ? .secondary : .primary)

                Text(medication.formattedSchedule)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if medication.silentReminder {
                Label("Silent", systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(medication.sound.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dimmed {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}
