import SwiftUI

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
}

