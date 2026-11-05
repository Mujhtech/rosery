import SwiftUI

struct FocusView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: RoserySheet?
    @State private var resetPresented = false

    var body: some View {
        GeometryReader { geometry in
            let expanded = RoseryLayout.usesExpandedTasbih(size: geometry.size, dynamicTypeSize: typeSize)
            let sculptureHeight = expanded ? min(430, max(250, geometry.size.height * 0.85)) : 310

            VStack(spacing: 0) {
                header
                    .frame(maxWidth: 1040)
                    .frame(maxWidth: .infinity)

                ScrollView {
                    TasbihStageLayout(expanded: expanded, sculptureHeight: sculptureHeight,
                                      minimumHeight: expanded ? max(0, geometry.size.height - 56) : 0,
                                      maximumCompactHeight: max(0, geometry.size.height - 108)) {
                        phrase

                        CounterSurface(large: true)
                            // A full-screen presentation moves between Duo displays on folding.
                            // Recreate its Metal surface while the shared count remains untouched.
                            .id(expanded)
                            .frame(maxWidth: 430)
                            .frame(maxWidth: .infinity)

                        details
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, expanded ? 0 : 28)
                    .padding(.bottom, expanded ? 0 : 24)
                    .frame(maxWidth: expanded ? 1040 : 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(RoseryTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .reading(let dhikr): ReadingView(dhikr: dhikr, isCounterReference: true)
            case .chooseDhikr: DhikrPickerView()
            case .settings: SettingsView()
            case .customizeBeads: BeadCustomizationView(appearance: store.beadAppearance)
            }
        }
        .confirmationDialog("Restart this count?", isPresented: $resetPresented, titleVisibility: .visible) {
            Button("Restart count", role: .destructive) { store.resetCounter() }
        } message: {
            Text("Your current count returns to zero. Completed rounds stay in Saved.")
        }
    }

    private var header: some View {
        HStack {
            RoundIconButton(symbol: "chevron.down", label: "Close focus mode") { dismiss() }
            Spacer()
            Text("FOCUS")
                .font(.system(size: 10, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(RoseryTheme.muted)
            Spacer()
            RoundIconButton(symbol: store.preferences.haptics ? "waveform" : "waveform.slash",
                            label: store.preferences.haptics ? "Turn haptics off" : "Turn haptics on") {
                store.updatePreferences { $0.haptics.toggle() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(minHeight: 56)
    }

    private var phrase: some View {
        VStack(spacing: 18) {
            Text(store.selectedDhikr.arabic)
                .font(RoseryTheme.arabic(46, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .fixedSize(horizontal: false, vertical: true)
            if store.preferences.transliteration {
                Text(store.selectedDhikr.transliteration)
                    .font(.system(.title3, weight: .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(store.selectedDhikr.subtitle)
                .font(.subheadline)
                .foregroundStyle(RoseryTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(RoseryTheme.ink)
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(spacing: 14) {
            CounterReadout(large: true)

            if store.progress.isComplete {
                focusCompletion
            } else {
                Text("Touch the beads to count")
                    .font(.subheadline)
                    .foregroundStyle(RoseryTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { sheet = .reading(store.selectedDhikr) } label: {
                Label("Meaning & source", systemImage: "text.book.closed")
                    .font(.footnote)
                    .foregroundStyle(RoseryTheme.muted)
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var focusCompletion: some View {
        VStack(spacing: 16) {
            Label("Round complete", systemImage: "checkmark.circle")
                .font(.body)
                .foregroundStyle(RoseryTheme.ink)
            if let next = store.nextAfterPrayer {
                completionButton("Continue with \(next.title)") { store.beginNextAfterPrayer() }
            } else if store.selectedDhikr.id == "allahu-akbar", !store.isPersonalTarget,
                      let finalReading = DhikrLibrary.reading(id: "tahlil") {
                completionButton("Read the hundredth remembrance") { sheet = .reading(finalReading) }
            } else {
                completionButton("Begin another round") { store.resetCounter() }
            }
        }
        .frame(maxWidth: 520)
    }

    private func completionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
    }

    private var controls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 20))
        return VStack(spacing: 16) {
            layout {
                Button { store.undo() } label: {
                    controlLabel("Undo", symbol: "arrow.uturn.backward")
                }
                .disabled(store.progress.count == 0)

                Button { resetPresented = true } label: {
                    controlLabel("Restart", symbol: "arrow.counterclockwise")
                }
                .disabled(store.progress.count == 0)

                LiveActivityControl(style: .focus)
            }
            .foregroundStyle(RoseryTheme.ink)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.top, 17)
        .padding(.bottom, 18)
        .background(RoseryTheme.canvas)
        .overlay(alignment: .top) {
            RoseryTheme.line.frame(height: 0.5)
                .padding(.horizontal, 26)
                .frame(maxWidth: 1040)
        }
    }

    private func controlLabel(_ title: String, symbol: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 7))
        return layout {
            Image(systemName: symbol)
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(.rect)
    }
}

struct DhikrPickerView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose a dhikr")
                        .font(.system(size: 32, weight: .semibold))
                        .tracking(-1.2)
                        .padding(.bottom, 5)
                    Text("Each dhikr keeps its own count, ready for when you return.")
                        .font(.subheadline)
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.bottom, 14)
                    ForEach(DhikrLibrary.counterPhrases) { dhikr in
                        Button {
                            store.select(dhikr)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(dhikr.title).font(.system(.body, weight: .medium))
                                    Text(dhikr.subtitle).font(.subheadline).foregroundStyle(RoseryTheme.muted)
                                    Text("\(dhikr.repetitions ?? 33) from the source")
                                        .font(.caption).foregroundStyle(RoseryTheme.muted)
                                }
                                Spacer()
                                Image(systemName: store.selectedDhikr.id == dhikr.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .light))
                            }
                            .padding(.vertical, 22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .bottom) { RoseryTheme.line.frame(height: 0.5) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.selectedDhikr.id == dhikr.id ? .isSelected : [])
                    }
                }
                .padding(24)
            }
            .background(RoseryTheme.canvas)
            .foregroundStyle(RoseryTheme.ink)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
