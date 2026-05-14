import Foundation

// MARK: - WatchMedication

struct WatchMedication: Codable, Identifiable {
    let id: UUID
    let name: String
    let scheduledHour: Int
    let scheduledMinute: Int
    let isEnabled: Bool
    let formattedSchedule: String
    let nextFireDateTimestamp: TimeInterval

    var nextFireDate: Date {
        Date(timeIntervalSince1970: nextFireDateTimestamp)
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var comps = DateComponents()
        comps.hour = scheduledHour
        comps.minute = scheduledMinute
        guard let date = Calendar.current.date(from: comps) else {
            return "\(scheduledHour):\(scheduledMinute)"
        }
        return formatter.string(from: date)
    }
}

// MARK: - WatchDataStore

@Observable
final class WatchDataStore {
    static let shared = WatchDataStore()

    private(set) var medications: [WatchMedication] = []
    private(set) var lastSyncDate: Date?

    private let medicationsKey = "watchMedications"
    private let lastSyncKey = "watchLastSync"

    private init() {
        load()
    }

    func update(medications: [WatchMedication]) {
        self.medications = medications
        self.lastSyncDate = Date()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(medications) else { return }
        UserDefaults.standard.set(data, forKey: medicationsKey)
        UserDefaults.standard.set(lastSyncDate?.timeIntervalSince1970, forKey: lastSyncKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: medicationsKey),
           let decoded = try? JSONDecoder().decode([WatchMedication].self, from: data) {
            medications = decoded
        }
        if let ts = UserDefaults.standard.object(forKey: lastSyncKey) as? TimeInterval {
            lastSyncDate = Date(timeIntervalSince1970: ts)
        }
    }
}
