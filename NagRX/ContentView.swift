import SwiftUI

struct ContentView: View {
    @State private var celebration = CelebrationManager.shared

    var body: some View {
        TabView {
            MedicationListView()
                .tabItem {
                    Label("Medications", systemImage: "pills")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }

            HelpView()
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
        }
        .tint(.red)
        .task {
            await NagScheduler.shared.sync()
        }
        .overlay {
            if celebration.isCelebrating {
                CelebrationView(medicationName: celebration.medicationName)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
    }
}

#Preview {
    ContentView()
}

