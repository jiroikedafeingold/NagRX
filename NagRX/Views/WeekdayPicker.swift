import SwiftUI

struct WeekdayPicker: View {
    @Binding var selectedWeekdays: Set<Int>

    // Calendar weekday symbols (index 0 = weekday 1 = Sunday)
    private let days: [(index: Int, short: String)] = {
        let formatter = DateFormatter()
        return (1...7).map { ($0, formatter.veryShortWeekdaySymbols[$0 - 1]) }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(days, id: \.index) { day in
                    Button {
                        if selectedWeekdays.contains(day.index) {
                            selectedWeekdays.remove(day.index)
                        } else {
                            selectedWeekdays.insert(day.index)
                        }
                    } label: {
                        Text(day.short)
                            .font(.system(.caption, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(
                                selectedWeekdays.contains(day.index)
                                    ? Color.red : Color(.systemGray5)
                            )
                            .foregroundStyle(
                                selectedWeekdays.contains(day.index)
                                    ? .white : .primary
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
