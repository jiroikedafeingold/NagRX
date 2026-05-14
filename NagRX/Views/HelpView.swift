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
                        detail: "NagRX schedules notifications for each medication at its configured time. You'll get an alert with sound and haptics that won't stop until you respond."
                    )
                    HelpRow(
                        icon: "arrow.clockwise",
                        iconColor: .red,
                        title: "Persistent Re-Alerts",
                        detail: "If you don't respond, NagRX will keep re-alerting you at the interval configured in Settings (default: every 5 minutes) until you acknowledge the reminder."
                    )
                }

                // MARK: Notifications
                Section("Notifications") {
                    HelpRow(
                        icon: "hand.tap.fill",
                        iconColor: .orange,
                        title: "Tapping the Banner = Snooze",
                        detail: "Tapping the notification banner snoozes the alarm for 15 minutes. You'll be reminded again after the snooze period."
                    )
                    HelpRow(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "\"I Took It\" Dismisses",
                        detail: "Long-press a notification and tap \"I Took It\" to dismiss the alarm completely. This stops all sounds, haptics, and clears the widget."
                    )
                    HelpRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        title: "Snooze",
                        detail: "Long-press a notification for snooze options: 15 minutes, 90 minutes, or 1 full day. The alarm will fire again after the snooze period. These same options are available on the Apple Watch."
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
                        detail: "Use the test alarm in Settings to fire a notification in 5 seconds and verify that sounds and haptics are working correctly."
                    )
                }

                // MARK: Tips
                Section("Tips") {
                    HelpRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "Grant Time Sensitive Notifications",
                        detail: "In iOS Settings → Notifications → NagRX, enable Time Sensitive Notifications so alarms can break through Focus modes."
                    )
                    HelpRow(
                        icon: "iphone.radiowaves.left.and.right",
                        iconColor: .yellow,
                        title: "Allow Background App Refresh",
                        detail: "Enable Background App Refresh for NagRX in iOS Settings so alarms stay up to date even when you're not using the app."
                    )
                    HelpRow(
                        icon: "square.stack.3d.up.fill",
                        iconColor: .yellow,
                        title: "64 Notification Limit",
                        detail: "iOS allows a maximum of 64 pending local notifications. NagRX automatically divides the budget across your medications so each one gets multiple upcoming reminders scheduled."
                    )
                    HelpRow(
                        icon: "xmark.app.fill",
                        iconColor: .red,
                        title: "Don't Force-Quit the App",
                        detail: "NagRX plays alarm audio through a background audio session, which lets it bypass silent mode. If you swipe the app away in the app switcher, iOS ends that session and alarms will fall back to standard notification sounds that respect silent mode."
                    )
                    HelpRow(
                        icon: "sunrise.fill",
                        iconColor: .yellow,
                        title: "Auto-Launch with Shortcuts",
                        detail: "Create a Shortcut automation to open NagRX every morning so it's always running in the background. Open the Shortcuts app → Automation → New Automation → Time of Day. Set a time before your first medication (e.g. 6:00 AM), choose \"Run Immediately\", then add the \"Open App\" action and select NagRX. Add in a final step which is \"Go to Home Screen\". This ensures NagRX is active and can play full-volume alarms even if your phone restarted overnight."
                    )
                }

                // MARK: Troubleshooting
                Section("Not Hearing Alerts?") {
                    HelpRow(
                        icon: "speaker.slash.fill",
                        iconColor: .red,
                        title: "Check the Silent Switch",
                        detail: "NagRX can bypass silent mode, but only when the app is running in the background. If you force-quit the app (swipe it away in the app switcher), iOS falls back to standard notification sounds which respect the silent switch. Make sure NagRX is running in the background."
                    )
                    HelpRow(
                        icon: "arrow.counterclockwise",
                        iconColor: .red,
                        title: "Reopen the App",
                        detail: "If you accidentally force-quit NagRX, simply open it again. The background audio session will restart and future alarms will play at full volume regardless of the silent switch."
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
                        detail: "The notification sound volume is controlled by your device's ringer volume, not the media volume. Use the volume buttons while not playing media to adjust it."
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
