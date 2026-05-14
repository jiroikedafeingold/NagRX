import SwiftUI
import SwiftData

struct MedicationListView: View {
    @Query private var medications: [Medication]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false
    @State private var selectedMedication: Medication?

    private var sortedMedications: [Medication] {
        return medications.sorted { a, b in
            if a.isEnabled != b.isEnabled { return a.isEnabled }
            return a.nextFireDate < b.nextFireDate
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if medications.isEmpty {
                    ContentUnavailableView(
                        "No Medications",
                        systemImage: "pills",
                        description: Text("Tap + to add your first medication reminder.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sortedMedications.enumerated()), id: \.element.id) { index, med in
                                Button {
                                    selectedMedication = med
                                } label: {
                                    MedicationRow(medication: med)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < sortedMedications.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddMedicationView()
            }
            .sheet(item: $selectedMedication) { med in
                EditMedicationView(medication: med)
            }
        }
    }

    private func deleteMedications(_ offsets: IndexSet, from sorted: [Medication]) {
        for index in offsets {
            let med = sorted[index]
            NagScheduler.shared.cancelMedication(med)
            modelContext.delete(med)
        }
        try? modelContext.save()
        Task { @MainActor in
            await NagScheduler.shared.sync()
        }
    }
}
