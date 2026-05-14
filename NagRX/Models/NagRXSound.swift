import Foundation
import UserNotifications

enum NagRXSound: String, CaseIterable, Codable, Identifiable, Sendable {
    case pebble        = "pebble"
    case brush         = "brush"
    case shaman        = "shaman"
    case zenCute       = "zenCute"
    case gozaimasu     = "gozaimasu"
    case jfk           = "jfk"
    case narita        = "narita"
    case accessGranted = "accessGranted"
    case positiveID    = "positiveID"
    case openChannel   = "openChannel"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pebble:        "Pebble"
        case .brush:         "Brush"
        case .shaman:        "Shaman"
        case .zenCute:       "Zen Cute"
        case .gozaimasu:     "Gozaimasu"
        case .jfk:           "JFK"
        case .narita:        "Narita"
        case .accessGranted: "Access Granted"
        case .positiveID:    "Positive ID"
        case .openChannel:   "Open Channel"
        }
    }

    /// The actual filename on disk (without extension).
    var fileName: String {
        switch self {
        case .pebble:        "Origin_ag_PEBBLE_short_1"
        case .brush:         "Origin_mg_BRUSH_short_1"
        case .shaman:        "Origin_mg_SHAMAN_short_1"
        case .zenCute:       "Zen_ag_CUTE_short"
        case .gozaimasu:     "Zen_mg_GOZAIMASU_LO_short"
        case .jfk:           "Zen_mg_JFK_LO_short"
        case .narita:        "Zen_mg_NARITA_LO_short"
        case .accessGranted: "Tek_mg_ACCESS-GRANTED_short_1"
        case .positiveID:    "Tek_mg_POSITIVE-ID_short_1"
        case .openChannel:   "Tek_xmg_OPEN-CHANNEL_short_1"
        }
    }

    static let fileExtension = "m4r"

    var notificationSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName + "." + Self.fileExtension))
    }
}
