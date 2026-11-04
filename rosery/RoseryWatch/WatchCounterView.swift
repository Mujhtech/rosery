import SwiftUI

enum WatchRoseryTheme {
    static let ink = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let muted = Color(red: 0.64, green: 0.66, blue: 0.63)
    static let accent = Color(red: 0.72, green: 0.62, blue: 0.43)

    static func arabic(_ size: CGFloat) -> Font {
        .custom("NotoNaskhArabic-Regular", size: size, relativeTo: .title2)
    }
}

private enum WatchCounterDestination: Hashable {
    case dhikr, target, options, reading(String)
}

struct WatchCounterView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var countFeedback = CountFeedback()

    var body: some View {
        NavigationStack {
            Group {
                if store.isReady {
                    counter
                } else {
                    firstSync
                }
            }
            .background(Color.black)
            .foregroundStyle(WatchRoseryTheme.ink)
            .navigationTitle("Rosery")
            .toolbar {
                if store.isReady {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: WatchCounterDestination.options) {
                            Image(systemName: "ellipsis")
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black)
                        }
                        .accessibilityLabel("Counter options")
                        .accessibilityIdentifier("watch.options")
                    }
                }
            }
            .navigationDestination(for: WatchCounterDestination.self) { destination in
                switch destination {
                case .dhikr: WatchDhikrPickerView()
                case .target: WatchTargetPickerView()
                case .options: WatchCounterOptionsView()
                case .reading(let id):
                    if let dhikr = DhikrLibrary.reading(id: id) {
                        WatchReadingDetailView(dhikr: dhikr)
                    }
                }
            }
        }
        .sensoryFeedback(trigger: countFeedback) { _, event in
            guard store.preferences.haptics, !isLuminanceReduced else { return nil }
            return event.completed ? .success : .selection
        }
    }

    private var counter: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 220 && !typeSize.isAccessibilitySize
            ScrollView {
                VStack(spacing: compact ? 4 : 8) {
                    NavigationLink(value: WatchCounterDestination.dhikr) {
                        VStack(spacing: 1) {
                            HStack(spacing: 5) {
                                Text(store.selectedDhikr.arabic)
                                    .font(WatchRoseryTheme.arabic(compact ? 20 : 27))
                                    .environment(\.layoutDirection, .rightToLeft)
                                    .fixedSize(horizontal: false, vertical: true)
                                if compact {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(WatchRoseryTheme.muted)
                                }
                            }
                            if !compact {
                                Text(store.selectedDhikr.title)
                                    .font(.caption2)
                                    .foregroundStyle(WatchRoseryTheme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change dhikr, currently \(store.selectedDhikr.title)")
                    .accessibilityIdentifier("watch.chooseDhikr")

                    ZStack(alignment: .bottom) {
                        countButton(compact: compact)
                        targetButton(compact: compact)
                            .padding(.bottom, compact ? 6 : 8)
                    }

                    if store.progress.isComplete {
                        completedRound
                    }

                    Button(action: store.undo) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.progress.count == 0)
                    .accessibilityLabel("Undo last count")
                    .accessibilityIdentifier("watch.undo")

                    if store.pendingCount > 0 || store.persistenceError != nil || store.hasConflictNotice {
                        WatchSyncStatusView()
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            }
        }
    }

    private func targetButton(compact: Bool) -> some View {
        NavigationLink(value: WatchCounterDestination.target) {
            HStack(spacing: 4) {
                Text("Target \(store.progress.target.formatted())")
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(compact ? .caption2 : .caption)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(WatchRoseryTheme.muted)
            .frame(maxWidth: compact ? 102 : 120, minHeight: compact ? 28 : 32)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change target")
        .accessibilityValue(store.progress.target.formatted())
        .accessibilityIdentifier("watch.target")
    }

    private func countButton(compact: Bool) -> some View {
        Button(action: increment) {
            ZStack {
                WatchBeadRing(progress: Double(store.progress.count) / Double(max(1, store.progress.target)))
                    .opacity(isLuminanceReduced ? 0.3 : 1)
                Text(store.progress.count.formatted())
                    .font(.system(size: compact ? 44 : 52, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 24)
                    .foregroundStyle(WatchRoseryTheme.ink)
                    .offset(y: compact ? -11 : -13)
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 104 : 128)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.progress.isComplete)
        .accessibilityLabel("Count \(store.selectedDhikr.title)")
        .accessibilityValue("\(store.progress.count) of \(store.progress.target)")
        .accessibilityHint(store.progress.isComplete ? "Round complete" : "Double tap to add one remembrance")
        .accessibilityIdentifier("watch.count")
    }

    private var completedRound: some View {
        VStack(spacing: 8) {
            Label("Round complete", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(WatchRoseryTheme.accent)
            if let next = store.nextAfterPrayer {
                Button("Continue with \(next.title)", action: store.beginNextAfterPrayer)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("watch.nextDhikr")
            } else {
                if store.selectedDhikr.id == "allahu-akbar", store.progress.target == 33,
                   let finalReading = DhikrLibrary.reading(id: "tahlil") {
                    NavigationLink("Hundredth remembrance",
                                   value: WatchCounterDestination.reading(finalReading.id))
                }
                Button("Begin another round") { store.restart() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("watch.newRound")
            }
        }
    }

    private var firstSync: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title2)
                    .foregroundStyle(WatchRoseryTheme.accent)
                    .accessibilityHidden(true)
                Text("Open Rosery on iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Sync your tasbih once to get started. You can then count on your watch while your iPhone is away.")
                    .font(.caption)
                    .foregroundStyle(WatchRoseryTheme.muted)
                    .multilineTextAlignment(.center)
                Button("Sync with iPhone", action: store.requestSync)
                    .accessibilityIdentifier("watch.initialSync")
                WatchSyncStatusView()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
    }

    private func increment() {
        let previousCount = store.progress.count
        store.increment()
        guard store.progress.count > previousCount else { return }
        countFeedback = CountFeedback(sequence: countFeedback.sequence + 1,
                                      completed: store.progress.isComplete)
    }

    private struct CountFeedback: Equatable {
        var sequence = 0
        var completed = false
    }
}

/// A static ring redraws only when the count changes; no timer runs in Always On mode.
private struct WatchBeadRing: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 5
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let highlighted = Int((min(1, max(0, progress)) * 33).rounded(.down))
            for index in 0..<33 {
                let angle = Double(index) / 33 * .pi * 2 - .pi / 2
                let point = CGPoint(x: center.x + cos(angle) * radius,
                                    y: center.y + sin(angle) * radius)
                let bead = CGRect(x: point.x - 2.8, y: point.y - 2.8, width: 5.6, height: 5.6)
                let color = index < highlighted ? WatchRoseryTheme.accent : WatchRoseryTheme.ink.opacity(0.25)
                context.fill(Path(ellipseIn: bead), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WatchDhikrPickerView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(DhikrLibrary.counterPhrases) { dhikr in
            Button {
                store.select(dhikr)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dhikr.title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(dhikr.arabic)
                            .font(WatchRoseryTheme.arabic(23))
                            .environment(\.layoutDirection, .rightToLeft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if store.selectedDhikr.id == dhikr.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(WatchRoseryTheme.accent)
                    }
                }
                .padding(.vertical, 3)
            }
            .accessibilityAddTraits(store.selectedDhikr.id == dhikr.id ? .isSelected : [])
        }
        .navigationTitle("Dhikr")
    }
}

private struct WatchTargetPickerView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var customTarget = ""
    @State private var crownTarget = 33.0
    @State private var editingContext: WatchRoundContext?
    @State private var pendingRestart: WatchTargetRestart?
    @State private var errorMessage: String?

    private var presets: [Int] {
        Array(Set([store.selectedDhikr.repetitions, 33, 100, 500, 1000].compactMap { $0 })).sorted()
    }

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.self) { target in
                    Button { apply(target) } label: {
                        HStack {
                            Text(target, format: .number)
                                .monospacedDigit()
                            Spacer()
                            if target == store.progress.target {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(WatchRoseryTheme.accent)
                            }
                        }
                    }
                    .accessibilityLabel("Set target to \(target)")
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Your target can differ from the source count.")
            }

            Section("Custom target") {
                TextField("1–10,000", text: $customTarget)
                    .accessibilityLabel("Custom target")
                    .accessibilityIdentifier("watch.customTarget")
                    .onChange(of: customTarget) { _, value in
                        if let target = Int(value), (1...10000).contains(target) {
                            crownTarget = Double(target)
                        }
                    }
                VStack(spacing: 4) {
                    Text(Int(crownTarget), format: .number)
                        .font(.title3)
                        .monospacedDigit()
                    Text("Or turn the Digital Crown")
                        .font(.caption2)
                        .foregroundStyle(WatchRoseryTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .focusable()
                .digitalCrownRotation($crownTarget, from: 1, through: 10000, by: 1,
                                      sensitivity: .low, isContinuous: false,
                                      isHapticFeedbackEnabled: store.preferences.haptics)
                .onChange(of: crownTarget) { _, value in customTarget = String(Int(value)) }
                .accessibilityLabel("Target with Digital Crown")
                .accessibilityValue(Int(crownTarget).formatted())

                Button("Apply target") {
                    guard let target = Int(customTarget.trimmingCharacters(in: .whitespacesAndNewlines)),
                          (1...10000).contains(target) else {
                        errorMessage = "Enter a whole number from 1 to 10,000."
                        return
                    }
                    apply(target)
                }
                .accessibilityIdentifier("watch.applyTarget")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WatchRoseryTheme.muted)
            }
        }
        .navigationTitle("Target")
        .onAppear {
            guard editingContext == nil else { return }
            editingContext = WatchRoundContext(store: store)
            customTarget = String(store.progress.target)
            crownTarget = Double(store.progress.target)
        }
        .confirmationDialog("Start at zero?", isPresented: showingRestart, titleVisibility: .visible) {
            Button("Restart with new target", role: .destructive, action: confirmRestart)
            Button("Cancel", role: .cancel) { pendingRestart = nil }
        } message: {
            if let pendingRestart {
                Text("Your current count is \(pendingRestart.context.count). A target of \(pendingRestart.target) starts a new round at zero.")
            }
        }
    }

    private var showingRestart: Binding<Bool> {
        Binding(get: { pendingRestart != nil }, set: { if !$0 { pendingRestart = nil } })
    }

    private func apply(_ target: Int) {
        guard let editingContext, editingContext.matchesRound(store) else {
            errorMessage = "This round changed. Go back and review the current count."
            return
        }
        errorMessage = nil
        if store.setTarget(target) {
            dismiss()
        } else if target < store.progress.count {
            pendingRestart = WatchTargetRestart(context: WatchRoundContext(store: store), target: target)
        } else {
            errorMessage = store.persistenceError ?? "The target could not be saved. Try again."
        }
    }

    private func confirmRestart() {
        guard let pendingRestart else { return }
        self.pendingRestart = nil
        guard pendingRestart.context.matchesRound(store),
              pendingRestart.context.count == store.progress.count else {
            errorMessage = "This round changed. Go back and review the current count."
            return
        }
        store.restart(target: pendingRestart.target)
        dismiss()
    }
}

private struct WatchCounterOptionsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRestart: WatchRoundContext?
    @State private var errorMessage: String?

    var body: some View {
        List {
            NavigationLink("Choose dhikr", value: WatchCounterDestination.dhikr)
            NavigationLink("Change target", value: WatchCounterDestination.target)
            NavigationLink("Meaning & source", value: WatchCounterDestination.reading(store.selectedDhikr.id))
            Button("Restart round", role: .destructive) {
                if store.progress.count == 0 {
                    store.restart()
                    dismiss()
                } else {
                    pendingRestart = WatchRoundContext(store: store)
                }
            }
            .accessibilityIdentifier("watch.restart")

            Section("iPhone sync") {
                WatchSyncStatusView()
                Button("Sync now", action: store.refresh)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WatchRoseryTheme.muted)
            }
        }
        .navigationTitle("Options")
        .confirmationDialog("Restart this round?", isPresented: showingRestart, titleVisibility: .visible) {
            Button("Restart at zero", role: .destructive) {
                guard let context = pendingRestart else { return }
                pendingRestart = nil
                guard context.matchesRound(store), context.count == store.progress.count else {
                    errorMessage = "This round changed. Review its count before restarting."
                    return
                }
                store.restart()
                dismiss()
            }
            Button("Cancel", role: .cancel) { pendingRestart = nil }
        } message: {
            Text("Your current count returns to zero. Completed rounds stay saved on iPhone.")
        }
    }

    private var showingRestart: Binding<Bool> {
        Binding(get: { pendingRestart != nil }, set: { if !$0 { pendingRestart = nil } })
    }
}

private struct WatchReadingDetailView: View {
    @Environment(WatchStore.self) private var store
    let dhikr: Dhikr

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(dhikr.arabic)
                    .font(WatchRoseryTheme.arabic(store.preferences.largeArabic ? 31 : 26))
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if store.preferences.transliteration {
                    Text(dhikr.transliteration)
                        .font(.caption)
                        .foregroundStyle(WatchRoseryTheme.muted)
                }
                Text(dhikr.meaning)
                    .font(.body)
                Text(dhikr.guidance)
                    .font(.caption)
                    .foregroundStyle(WatchRoseryTheme.muted)
                Divider()
                ForEach(dhikr.sources) { source in
                    Text(source.title)
                        .font(.caption2)
                        .foregroundStyle(WatchRoseryTheme.muted)
                }
                Text("Open Rosery on iPhone for source links.")
                    .font(.caption2)
                    .foregroundStyle(WatchRoseryTheme.muted)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .foregroundStyle(WatchRoseryTheme.ink)
        .navigationTitle(dhikr.title)
    }
}

private struct WatchSyncStatusView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let error = store.persistenceError {
                Label(error, systemImage: "exclamationmark.circle")
            } else {
                Text(store.statusMessage)
            }
        }
        .font(.caption2)
        .foregroundStyle(WatchRoseryTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchRoundContext {
    let dhikrID: String
    let generation: UUID
    let count: Int

    @MainActor init(store: WatchStore) {
        dhikrID = store.selectedDhikr.id
        generation = store.progress.generation
        count = store.progress.count
    }

    @MainActor func matchesRound(_ store: WatchStore) -> Bool {
        dhikrID == store.selectedDhikr.id && generation == store.progress.generation
    }
}

private struct WatchTargetRestart {
    let context: WatchRoundContext
    let target: Int
}
