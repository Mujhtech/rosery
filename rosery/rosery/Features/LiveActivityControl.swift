import SwiftUI
import UIKit

struct LiveActivityControl: View {
    enum Style { case inline, focus, settings }

    @Environment(RoseryStore.self) private var store
    @Environment(TasbihLiveActivityController.self) private var liveActivities
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isUpdating = false
    @State private var errorMessage: String?
    var style: Style = .inline

    private var title: String {
        liveActivities.isActive ? "End Live Activity" : "Show on Lock Screen"
    }

    var body: some View {
        Button {
            isUpdating = true
            Task { @MainActor in
                defer { isUpdating = false }
                if liveActivities.isActive {
                    await liveActivities.stop()
                } else {
                    store.refreshFromShared()
                    guard store.persistenceError == nil else {
                        errorMessage = "Your count could not be loaded. Try reopening Rosery before starting a Live Activity."
                        return
                    }
                    await liveActivities.start(snapshot: store.tasbihSnapshot)
                }
                errorMessage = liveActivities.errorMessage
            }
        } label: {
            if style == .focus {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(HStackLayout(spacing: 12))
                    : AnyLayout(VStackLayout(spacing: 7))
                layout {
                    Image(systemName: liveActivities.isActive ? "stop.circle" : "waveform.path")
                    Text(liveActivities.isActive ? "End live" : "Go live").font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(.rect)
            } else {
                Label(title, systemImage: liveActivities.isActive ? "stop.circle" : "waveform.path")
                    .font(style == .inline ? .footnote : .body)
                    .frame(maxWidth: style == .settings ? .infinity : nil,
                           minHeight: 44, alignment: style == .settings ? .leading : .center)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(style == .inline ? RoseryTheme.muted : RoseryTheme.ink)
        .disabled(isUpdating || (store.progress.isComplete && !liveActivities.isActive))
        .opacity(isUpdating ? 0.5 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(liveActivities.isActive
                           ? "Keeps your current count in Rosery."
                           : "Count this round from your Lock Screen or Dynamic Island.")
        .accessibilityIdentifier("tasbih.liveActivity")
        .alert("Live tasbih", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            if !liveActivities.isAvailable {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct LiveActivitySettingsView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(TasbihLiveActivityController.self) private var liveActivities
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Text("Keep your current tasbih round on your Lock Screen and, on supported iPhones, in the Dynamic Island. Add a count or undo without reopening Rosery.")
                    .font(.subheadline)
                    .foregroundStyle(RoseryTheme.muted)
                    .padding(.vertical, 4)
            }
            .listRowBackground(RoseryTheme.surface)

            Section {
                LabeledContent(store.selectedDhikr.title) {
                    Text("\(store.progress.count.formatted()) / \(store.progress.target.formatted())")
                        .monospacedDigit()
                }
                LiveActivityControl(style: .settings)
            } header: {
                Text("Current round")
            } footer: {
                Text(store.progress.isComplete
                     ? "Begin another round to start a Live Activity."
                     : "The activity ends when you finish, restart, change dhikr, or change your target. Ending it yourself keeps your count.")
            }
            .listRowBackground(RoseryTheme.surface)

            if !liveActivities.isAvailable {
                Section {
                    Text("Live Activities are turned off for Rosery. You can enable them in iPhone Settings.")
                        .font(.subheadline)
                        .foregroundStyle(RoseryTheme.muted)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                .listRowBackground(RoseryTheme.surface)
            }
        }
        .foregroundStyle(RoseryTheme.ink)
        .tint(RoseryTheme.ink)
        .scrollContentBackground(.hidden)
        .background(RoseryTheme.canvas)
        .navigationTitle("Live tasbih")
        .navigationBarTitleDisplayMode(.inline)
    }
}
