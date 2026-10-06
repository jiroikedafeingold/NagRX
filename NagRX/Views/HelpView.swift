import SwiftUI

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                // MARK: How It Works
                Section("How It Works") {
                    HelpRow(
                        icon: "pills.fill",
                        iconColor: .red,
                        title: "Add Your Medications",
                        detail: "Tap the + button on the Medications tab to add each medication you need to remember. Set the time of day and how often you take it — daily, specific days of the week, or monthly."
                    )
                    HelpRow(
                        icon: "bell.badge.fill",
                        iconColor: .red,
                        title: "Automatic Reminders",
                        detail: "NagRX sets a real alarm for each medication at its configured time — the same kind the Clock app uses — so it rings even when your iPhone is on silent or in a Focus, and even if NagRX isn't open."
                    )
                    HelpRow(
                        icon: "arrow.clockwise",
                        iconColor: .red,
                        title: "Persistent Re-Alerts",
                        detail: "If you don't take it, NagRX keeps ringing again at the interval configured in Settings (default: every 5 minutes) until you confirm the dose."
                    )
                }

                // MARK: Alarms
                Section("Alarms") {
                    HelpRow(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Stop = \"I Took It\"",
                        detail: "Tap Stop on the alarm once you've taken your medication. That ends the reminders for that dose and clears the widget."
                    )
                    HelpRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        title: "Snooze",
                        detail: "Tap Snooze to ring again in 15 minutes. While snoozed, a countdown shows in the Dynamic Island and on the Lock Screen. After that, re-alerts continue at your usual interval."
                    )
                    HelpRow(
                        icon: "bell.badge.fill",
                        iconColor: .orange,
                        title: "If Alarms Are Off",
                        detail: "If you don't allow alarms, NagRX sends notifications instead, which follow your ringer switch. Long-press one for \"I Took It\" or to snooze 15 minutes, 90 minutes or a day. Only the newest notification stays in Notification Center, and it clears itself after 30 minutes."
                    )
                }

                // MARK: Scheduling
                Section("Scheduling") {
                    HelpRow(
                        icon: "calendar",
                        iconColor: .blue,
                        title: "Daily",
                        detail: "The default schedule. The medication reminder fires at the same time every day."
                    )
                    HelpRow(
                        icon: "calendar.badge.clock",
                        iconColor: .blue,
                        title: "Weekly",
                        detail: "Select specific days of the week (e.g. Mon, Wed, Fri) and a time. The reminder fires only on those days."
                    )
                    HelpRow(
                        icon: "calendar.badge.plus",
                        iconColor: .blue,
                        title: "Monthly",
                        detail: "Choose a specific day of the month (1st–31st), or \"First day\" or \"Last day\" of each month. The reminder fires once per month at the chosen time."
                    )
                }

                // MARK: Widget
                Section("Widget") {
                    HelpRow(
                        icon: "rectangle.on.rectangle",
                        iconColor: .red,
                        title: "Home Screen & Lock Screen",
                        detail: "Add NagRX widgets to your home screen or lock screen. When a medication is due, the widget turns red and shows which medications need attention."
                    )
                    HelpRow(
                        icon: "hand.tap.fill",
                        iconColor: .red,
                        title: "Tap Widget to Dismiss",
                        detail: "When a medication is due, tapping the widget opens the app and dismisses all active alarms — the same as tapping \"I Took It\" on the notification."
                    )
                }

                // MARK: Settings
                Section("Settings") {
                    HelpRow(
                        icon: "speaker.wave.2.fill",
                        iconColor: .red,
                        title: "Alert Sound",
                        detail: "Choose from 10 built-in alert sounds. The selected sound is used as the default for new medications. Each medication can also have its own sound."
                    )
                    HelpRow(
                        icon: "slider.horizontal.3",
                        iconColor: .red,
                        title: "Re-Alert Interval",
                        detail: "Control how many minutes between re-alerts if you don't respond. Default is 5 minutes. Can be set from 1 to 10 minutes."
                    )
                    HelpRow(
                        icon: "bell.badge",
                        iconColor: .red,
                        title: "Test Alarm",
                        detail: "Use the test alarm in Settings to ring an alarm in 5 seconds and check that it sounds the way you expect."
                    )
                }

                // MARK: Tips
                Section("Tips") {
                    HelpRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "Allow Alarms",
                        detail: "If doses aren't ringing, check Settings → Alarms in NagRX. If it says alarms are off, turn them back on for NagRX in iOS Settings."
                    )
                    HelpRow(
                        icon: "iphone.radiowaves.left.and.right",
                        iconColor: .yellow,
                        title: "Allow Background App Refresh",
                        detail: "Enable Background App Refresh for NagRX in iOS Settings so upcoming doses stay booked even when you haven't opened the app for a while."
                    )
                }

                // MARK: Troubleshooting
                Section("Not Hearing Alerts?") {
                    HelpRow(
                        icon: "speaker.slash.fill",
                        iconColor: .red,
                        title: "Check That Alarms Are Allowed",
                        detail: "NagRX's alarms ring through the silent switch and Focus. If you turned alarms off for NagRX, it uses notifications instead, and those follow the silent switch."
                    )
                    HelpRow(
                        icon: "bell.slash.fill",
                        iconColor: .orange,
                        title: "Check Notification Settings",
                        detail: "Go to iOS Settings → Notifications → NagRX and make sure Allow Notifications is on, Sounds is enabled, and Time Sensitive Notifications is turned on."
                    )
                    HelpRow(
                        icon: "speaker.wave.3.fill",
                        iconColor: .orange,
                        title: "Check Device Volume",
                        detail: "Alarm and notification volume follow your ringer volume, not the media volume. Use the volume buttons while not playing media to adjust it."
                    )
                }

                // MARK: Credits
                Section("Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alert Sounds")
                            .font(.body.weight(.medium))
                        Text("The ringtone sounds included in NagRX were created by **Jeff Essex** and **Joel Hladecek**.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://www.theinteractivist.com/free-ringtones-iringpro/")!) {
                            Label("theinteractivist.com", systemImage: "link")
                                .font(.footnote)
                        }
                        .tint(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Help")
        }
    }
}

// MARK: - HelpRow

private struct HelpRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
