import SwiftUI

/// Keeps an editor attached to the dhikr and round it was opened for.
struct TargetEditingContext: Identifiable {
    let id = UUID()
    let dhikrID: String
    let generation: UUID
    let title: String
    let sourceTarget: Int?
    let initialTarget: Int

    init(store: RoseryStore) {
        dhikrID = store.selectedDhikr.id
        generation = store.progress.generation
        title = store.selectedDhikr.title
        sourceTarget = store.selectedDhikr.repetitions
        initialTarget = store.progress.target
    }

    var presets: [Int] {
        Array(Set([33, 100, initialTarget] + [sourceTarget].compactMap { $0 })).sorted()
    }
}

struct TargetPickerView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var customFocused: Bool
    @State private var selectedPreset: Int?
    @State private var customTarget = ""
    @State private var pendingResetTarget: Int?
    @State private var resetPresented = false
    @State private var saveError: String?

    let context: TargetEditingContext

    init(context: TargetEditingContext) {
        self.context = context
        _selectedPreset = State(initialValue: context.initialTarget)
    }

    private var proposedTarget: Int? {
        if let selectedPreset { return selectedPreset }
        let text = customTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.allSatisfy({ $0.wholeNumberValue != nil }) else { return nil }
        let digits = text.compactMap(\.wholeNumberValue).map(String.init).joined()
        guard let value = Int(digits), (1...10_000).contains(value) else { return nil }
        return value
    }

    private var isCurrentRound: Bool {
        store.selectedDhikr.id == context.dhikrID && store.progress.generation == context.generation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(context.title) {
                        Text("Count \(store.progress.count.formatted())")
                            .monospacedDigit()
                            .foregroundStyle(RoseryTheme.muted)
                    }
                } footer: {
                    if let sourceTarget = context.sourceTarget {
                        Text("Source guidance: \(sourceTarget) repetitions. Other values are personal targets.")
                    } else {
                        Text("Choose a personal target for this round.")
                    }
                }
                .listRowBackground(RoseryTheme.surface)

                Section("Presets") {
                    ForEach(context.presets, id: \.self) { target in
                        Button {
                            selectedPreset = target
                            customFocused = false
                            saveError = nil
                        } label: {
                            HStack(spacing: 12) {
                                Text(target, format: .number)
                                    .monospacedDigit()
                                Text(target == context.sourceTarget ? "Source guidance" : "Personal target")
                                    .font(.subheadline)
                                    .foregroundStyle(RoseryTheme.muted)
                                Spacer()
                                if selectedPreset == target {
                                    Image(systemName: "checkmark")
                                        .font(.system(.subheadline, weight: .semibold))
                                }
                            }
                            .frame(minHeight: 32)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(target), \(target == context.sourceTarget ? "source guidance" : "personal target")")
                        .accessibilityAddTraits(selectedPreset == target ? .isSelected : [])
                        .accessibilityIdentifier("target.preset.\(target)")
                    }
                }
                .listRowBackground(RoseryTheme.surface)

                Section {
                    TextField("Enter a number", text: $customTarget)
                        .keyboardType(.numberPad)
                        .focused($customFocused)
                        .onChange(of: customFocused) { _, focused in
                            if focused { selectedPreset = nil; saveError = nil }
                        }
                        .onChange(of: customTarget) {
                            selectedPreset = nil
                            saveError = nil
                        }
                        .accessibilityLabel("Custom target")
                        .accessibilityHint("Enter a whole number from 1 to 10,000")
                        .accessibilityIdentifier("target.custom")
                } header: {
                    Text("Custom target")
                } footer: {
                    Text("Enter a whole number from 1 to 10,000. Your count is kept unless the new target is lower than your count.")
                }
                .listRowBackground(RoseryTheme.surface)

                if !isCurrentRound {
                    message("This round has changed. Close this sheet and reopen Target to edit the current round.")
                } else if let saveError {
                    message(saveError)
                } else if selectedPreset == nil, !customTarget.isEmpty, proposedTarget == nil {
                    message("Choose a whole number from 1 to 10,000.")
                }
            }
            .foregroundStyle(RoseryTheme.ink)
            .tint(RoseryTheme.ink)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(RoseryTheme.canvas)
            .navigationTitle("Set target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("target.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .disabled(proposedTarget == nil || !isCurrentRound)
                        .accessibilityIdentifier("target.apply")
                }
            }
            .confirmationDialog("Reset count for this target?", isPresented: $resetPresented, titleVisibility: .visible) {
                if let target = pendingResetTarget {
                    Button("Reset to 0 and set target \(target)", role: .destructive) {
                        confirmReset(target: target)
                    }
                    .accessibilityIdentifier("target.reset-confirm")
                }
                Button("Cancel", role: .cancel) { pendingResetTarget = nil }
            } message: {
                Text("Your current count is above the new target. Applying it starts a new round at zero. Completed rounds stay in Saved.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func message(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.footnote)
                .foregroundStyle(RoseryTheme.muted)
                .accessibilityIdentifier("target.message")
        }
        .listRowBackground(RoseryTheme.surface)
    }

    private func apply() {
        guard let target = proposedTarget else { return }
        customFocused = false
        saveError = nil
        store.refreshFromShared()
        guard isCurrentRound else { return }

        if target < store.progress.count {
            requestReset(target: target)
        } else if store.setTarget(target, expectedID: context.dhikrID, expectedGeneration: context.generation) {
            dismiss()
        } else if isCurrentRound, store.persistenceError == nil, target < store.progress.count {
            // A widget may have advanced beyond the proposed target during the save transaction.
            requestReset(target: target)
        } else if isCurrentRound {
            saveError = "Your target could not be saved. Please try again."
        }
    }

    private func requestReset(target: Int) {
        pendingResetTarget = target
        resetPresented = true
    }

    private func confirmReset(target: Int) {
        pendingResetTarget = nil
        store.refreshFromShared()
        guard isCurrentRound else { return }
        if store.resetCounter(target: target, expectedID: context.dhikrID, expectedGeneration: context.generation) {
            dismiss()
        } else if isCurrentRound {
            saveError = "Your target could not be saved. Please try again."
        }
    }
}
