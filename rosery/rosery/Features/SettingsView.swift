import SwiftUI

struct SettingsView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(ReminderController.self) private var reminders
    @Environment(TasbihLiveActivityController.self) private var liveActivities
    @Environment(\.dismiss) private var dismiss
    @State private var beadEditorPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 15) {
                        RosetteMark().frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("rosery").font(.system(size: 30, weight: .semibold)).tracking(-1.4)
                            Text("Your daily remembrance")
                                .font(.subheadline)
                                .foregroundStyle(RoseryTheme.muted)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(RoseryTheme.surface)

                Section("The feel") {
                    Button { beadEditorPresented = true } label: {
                        HStack {
                            Label("Customize beads", systemImage: "paintbrush.pointed")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(RoseryTheme.muted)
                        }
                    }
                    Toggle(isOn: Binding(get: { store.preferences.haptics }, set: { value in
                        store.updatePreferences { $0.haptics = value }
                    })) {
                        Label("Gentle haptics", systemImage: "waveform")
                    }
                    Picker("Appearance", selection: Binding(get: { store.preferences.appearance }, set: { value in
                        store.updatePreferences { $0.appearance = value }
                    })) {
                        ForEach(AppAppearance.allCases) { value in Text(value.title).tag(value) }
                    }
                }
                .listRowBackground(RoseryTheme.surface)

                Section("Your routine") {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        HStack {
                            Label("Daily reminder", systemImage: "bell")
                            Spacer()
                            Text(reminders.summary)
                                .font(.subheadline)
                                .foregroundStyle(RoseryTheme.muted)
                        }
                    }
                    .accessibilityIdentifier("settings.reminder")

                    NavigationLink {
                        LiveActivitySettingsView()
                    } label: {
                        HStack {
                            Label("Live tasbih", systemImage: "waveform.path")
                            Spacer()
                            Text(liveActivities.isActive ? "Active" : "Off")
                                .font(.subheadline)
                                .foregroundStyle(RoseryTheme.muted)
                        }
                    }
                    .accessibilityIdentifier("settings.liveActivity")
                }
                .listRowBackground(RoseryTheme.surface)

                Section("Your reading") {
                    Toggle(isOn: Binding(get: { store.preferences.transliteration }, set: { value in
                        store.updatePreferences { $0.transliteration = value }
                    })) {
                        Label("Show transliteration", systemImage: "textformat.abc")
                    }
                    Toggle(isOn: Binding(get: { store.preferences.largeArabic }, set: { value in
                        store.updatePreferences { $0.largeArabic = value }
                    })) {
                        Label("Larger Arabic text", systemImage: "textformat.size")
                    }
                }
                .listRowBackground(RoseryTheme.surface)

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Care in every word")
                            .font(.system(.body, weight: .medium))
                        Text("Each reading includes a Qur’an or hadith reference. Open its source to read the complete context. English meanings and transliterations are reading aids.")
                            .font(.subheadline)
                            .foregroundStyle(RoseryTheme.muted)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 7)
                }
                .listRowBackground(RoseryTheme.surface)

                Section {
                    Label("Your bookmarks and progress stay on this device. All readings are available offline; source links open online.", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.vertical, 7)
                }
                .listRowBackground(RoseryTheme.surface)
            }
            .foregroundStyle(RoseryTheme.ink)
            .tint(RoseryTheme.ink)
            .scrollContentBackground(.hidden)
            .background(RoseryTheme.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $beadEditorPresented) {
            BeadCustomizationView(appearance: store.beadAppearance)
        }
    }
}
