import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    @Environment(ReminderController.self) private var reminders

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminder", isOn: Binding(get: { reminders.preferences.isEnabled }, set: { enabled in
                    Task { await reminders.setEnabled(enabled) }
                }))
                .accessibilityIdentifier("reminder.enabled")
                .disabled(reminders.isUpdating)

                DatePicker("Time", selection: Binding(get: { reminders.time }, set: { date in
                    Task { await reminders.setTime(date) }
                }), displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("reminder.time")
                .disabled(reminders.isUpdating)
            } footer: {
                Text("One gentle reminder each day at your chosen local time.")
            }
            .listRowBackground(RoseryTheme.surface)

            Section {
                if reminders.isUpdating {
                    ProgressView("Updating reminder…")
                } else {
                    Text(reminders.summary)
                        .accessibilityIdentifier("reminder.status")
                }

                if let message = reminders.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(RoseryTheme.muted)
                        .accessibilityIdentifier("reminder.error")
                    Button("Try again") { Task { await reminders.refresh() } }
                        .disabled(reminders.isUpdating)
                }

                if reminders.status == .needsPermission {
                    Button("Allow notifications") { Task { await reminders.setEnabled(true) } }
                        .disabled(reminders.isUpdating)
                }

                if reminders.needsSettings,
                   let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    Link("Open notification settings", destination: url)
                        .accessibilityIdentifier("reminder.open-settings")
                }
            } footer: {
                Text("Delivery follows your notification and Focus settings. Turn the reminder off here at any time.")
            }
            .listRowBackground(RoseryTheme.surface)
        }
        .foregroundStyle(RoseryTheme.ink)
        .tint(RoseryTheme.ink)
        .scrollContentBackground(.hidden)
        .background(RoseryTheme.canvas)
        .navigationTitle("Daily reminder")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reminders.refresh() }
    }
}
