import Foundation

enum ScheduleFrequency: String, CaseIterable, Codable, Identifiable {
    case daily        = "daily"
    case everyOtherWeek = "everyOtherWeek"
    case weekly       = "weekly"
    case monthly      = "monthly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily:          "Daily"
        case .everyOtherWeek: "Every other week (daily)"
        case .weekly:         "Weekly"
        case .monthly:        "Monthly"
        }
    }
}
