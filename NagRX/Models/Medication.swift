import Foundation
import SwiftData

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var scheduledHour: Int = 8
    var scheduledMinute: Int = 0
    var isEnabled: Bool = true
    var selectedSound: String = "pebble"
    var createdAt: Date = Date()

    // Schedule frequency (defaults ensure lightweight SwiftData migration)
    var frequencyRaw: String = "daily"
    var weeklyDaysBitmask: Int = 0   // bit 0=Sun, bit 1=Mon, ..., bit 6=Sat
    var monthlyDay: Int = 1          // 0=first day, 1-31=specific, 32=last day
    var biweeklyStartTimestamp: TimeInterval = 0  // start of the first "on" week (Monday)
    var silentReminder: Bool = false              // notification only, no audible alarm

    // MARK: - Computed Accessors

    var sound: NagRXSound {
        NagRXSound(rawValue: selectedSound) ?? .pebble
    }

    var frequency: ScheduleFrequency {
        get { ScheduleFrequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    var selectedWeekdays: Set<Int> {
        get {
            var result = Set<Int>()
            for i in 1...7 {
                if weeklyDaysBitmask & (1 << (i - 1)) != 0 {
                    result.insert(i)
                }
            }
            return result
        }
        set {
            weeklyDaysBitmask = 0
            for day in newValue {
                weeklyDaysBitmask |= (1 << (day - 1))
            }
        }
    }

    var biweeklyStartDate: Date {
        get { Date(timeIntervalSince1970: biweeklyStartTimestamp) }
        set { biweeklyStartTimestamp = newValue.timeIntervalSince1970 }
    }

    /// Returns true if the given date falls in an "on" week for the every-other-week schedule.
    func isOnWeek(for date: Date) -> Bool {
        let cal = Calendar.current
        let startMonday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: biweeklyStartDate)
        let targetMonday = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let start = cal.date(from: startMonday),
              let target = cal.date(from: targetMonday) else { return true }
        let weeks = cal.dateComponents([.weekOfYear], from: start, to: target).weekOfYear ?? 0
        return abs(weeks) % 2 == 0
    }

    // MARK: - Fire Dates

    /// Returns the next `limit` fire dates for this medication.
    func nextFireDates(limit: Int = 1) -> [Date] {
        let cal = Calendar.current
        let now = Date()

        switch frequency {
        case .daily:
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = scheduledHour
            comps.minute = scheduledMinute
            comps.second = 0
            guard let todayFire = cal.date(from: comps) else { return [] }
            let first = todayFire > now ? todayFire : cal.date(byAdding: .day, value: 1, to: todayFire)!
            return (0..<limit).compactMap { offset in
                cal.date(byAdding: .day, value: offset, to: first)
            }

        case .everyOtherWeek:
            var results: [Date] = []
            var searchDate = now
            let maxSearch = cal.date(byAdding: .day, value: 120, to: now)!
            while results.count < limit, searchDate < maxSearch {
                if isOnWeek(for: searchDate) {
                    var comps = cal.dateComponents([.year, .month, .day], from: searchDate)
                    comps.hour = scheduledHour
                    comps.minute = scheduledMinute
                    comps.second = 0
                    if let candidate = cal.date(from: comps), candidate > now {
                        results.append(candidate)
                    }
                }
                searchDate = cal.date(byAdding: .day, value: 1, to: searchDate)!
            }
            return results

        case .weekly:
            guard !selectedWeekdays.isEmpty else { return [] }
            var results: [Date] = []
            var searchDate = now
            // Search up to 60 days ahead to find enough occurrences
            let maxSearch = cal.date(byAdding: .day, value: 60, to: now)!
            while results.count < limit, searchDate < maxSearch {
                let weekday = cal.component(.weekday, from: searchDate)
                if selectedWeekdays.contains(weekday) {
                    var comps = cal.dateComponents([.year, .month, .day], from: searchDate)
                    comps.hour = scheduledHour
                    comps.minute = scheduledMinute
                    comps.second = 0
                    if let candidate = cal.date(from: comps), candidate > now {
                        results.append(candidate)
                    }
                }
                searchDate = cal.date(byAdding: .day, value: 1, to: searchDate)!
            }
            return results

        case .monthly:
            var results: [Date] = []
            var searchMonth = cal.dateComponents([.year, .month], from: now)
            // Search up to 12 months ahead
            for _ in 0..<12 {
                guard results.count < limit else { break }
                guard let monthDate = cal.date(from: searchMonth) else { break }
                let range = cal.range(of: .day, in: .month, for: monthDate)!
                let lastDay = range.upperBound - 1

                let resolvedDay: Int
                if monthlyDay == 0 {
                    resolvedDay = 1
                } else if monthlyDay == 32 {
                    resolvedDay = lastDay
                } else {
                    resolvedDay = min(monthlyDay, lastDay)
                }

                var comps = searchMonth
                comps.day = resolvedDay
                comps.hour = scheduledHour
                comps.minute = scheduledMinute
                comps.second = 0
                if let candidate = cal.date(from: comps), candidate > now {
                    results.append(candidate)
                }

                // Advance to next month
                let next = cal.date(byAdding: .month, value: 1, to: monthDate)!
                searchMonth = cal.dateComponents([.year, .month], from: next)
            }
            return results
        }
    }

    /// Convenience: the single next fire date.
    var nextFireDate: Date {
        nextFireDates(limit: 1).first ?? Date()
    }

    // MARK: - Display

    /// Formatted time string for display (e.g., "8:00 AM").
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let cal = Calendar.current
        var comps = DateComponents()
        comps.hour = scheduledHour
        comps.minute = scheduledMinute
        guard let date = cal.date(from: comps) else { return "\(scheduledHour):\(scheduledMinute)" }
        return formatter.string(from: date)
    }

    /// Full schedule description for list display.
    var formattedSchedule: String {
        switch frequency {
        case .daily:
            return "Daily at \(formattedTime)"
        case .everyOtherWeek:
            return "Every other week, daily at \(formattedTime)"
        case .weekly:
            let formatter = DateFormatter()
            let symbols = formatter.shortWeekdaySymbols!
            let dayNames = selectedWeekdays.sorted().map { symbols[$0 - 1] }
            if dayNames.isEmpty { return "Weekly at \(formattedTime)" }
            return dayNames.joined(separator: ", ") + " at \(formattedTime)"
        case .monthly:
            let dayStr: String
            if monthlyDay == 0 {
                dayStr = "1st"
            } else if monthlyDay == 32 {
                dayStr = "Last day"
            } else {
                let formatter = NumberFormatter()
                formatter.numberStyle = .ordinal
                dayStr = formatter.string(from: NSNumber(value: monthlyDay)) ?? "\(monthlyDay)"
            }
            return "\(dayStr) of each month at \(formattedTime)"
        }
    }

    /// Stable identifier for notification scheduling.
    var notificationIdentifier: String {
        "nagrx_\(id.uuidString)"
    }

    // MARK: - Init

    init(
        name: String,
        scheduledHour: Int,
        scheduledMinute: Int,
        selectedSound: String = "pebble",
        frequency: ScheduleFrequency = .daily,
        weeklyDaysBitmask: Int = 0,
        monthlyDay: Int = 1,
        biweeklyStartTimestamp: TimeInterval = 0,
        silentReminder: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.scheduledHour = scheduledHour
        self.scheduledMinute = scheduledMinute
        self.selectedSound = selectedSound
        self.frequencyRaw = frequency.rawValue
        self.weeklyDaysBitmask = weeklyDaysBitmask
        self.monthlyDay = monthlyDay
        self.biweeklyStartTimestamp = biweeklyStartTimestamp
        self.silentReminder = silentReminder
        self.createdAt = Date()
    }
}
