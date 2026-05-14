import SwiftUI

struct MonthlyDayPicker: View {
    @Binding var monthlyDay: Int

    var body: some View {
        Picker("Day of month", selection: $monthlyDay) {
            Text("First day").tag(0)
            ForEach(1...31, id: \.self) { day in
                Text(ordinalString(day)).tag(day)
            }
            Text("Last day").tag(32)
        }
    }

    private func ordinalString(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}
