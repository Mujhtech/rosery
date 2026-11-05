import SwiftUI

struct TodayView: View {
    @Environment(RoseryStore.self) private var store
    @Environment(TasbihLiveActivityController.self) private var liveActivities
    @Environment(\.dynamicTypeSize) private var typeSize
    let showSheet: (RoserySheet) -> Void
    let openFocus: () -> Void
    let openCollection: (DhikrCollection?) -> Void
    var showsBeads = true

    var body: some View {
        GeometryReader { geometry in
            let expanded = RoseryLayout.usesExpandedTasbih(size: geometry.size, dynamicTypeSize: typeSize)
            ScrollView {
                VStack(spacing: 0) {
                    TasbihStageLayout(
                        expanded: expanded,
                        sculptureHeight: expanded
                            ? min(480, max(220, geometry.size.height - 128))
                            : min(360, max(250, geometry.size.height * 0.43)),
                        minimumHeight: expanded ? max(0, geometry.size.height - 128) : 0,
                        maximumCompactHeight: max(0, geometry.size.height - 43)
                    ) {
                        phrase
                        if showsBeads {
                            CounterSurface()
                        } else {
                            Color.clear
                        }
                        countingDetails
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, expanded ? 6 : 25)
                    .padding(.bottom, 18)

                    Spacer(minLength: 0)
                    discoverLibrary
                        .padding(.horizontal, 28)
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var countingDetails: some View {
        VStack(spacing: 10) {
            CounterReadout()
            if store.progress.isComplete {
                RoundCompletionView(openReading: { showSheet(.reading($0)) })
            } else {
                HStack(spacing: 8) {
                    Button { store.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 17, weight: .light))
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Undo last count")
                    .disabled(store.progress.count == 0)
                    Text("Touch the beads to count")
                        .font(.system(size: 12))
                        .foregroundStyle(RoseryTheme.muted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Button(action: openFocus) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .light))
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Open focus mode")
                }
                .foregroundStyle(RoseryTheme.ink)
                .buttonStyle(.plain)
            }
            if !store.progress.isComplete || liveActivities.isActive {
                LiveActivityControl()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var discoverLibrary: some View {
        Button { openCollection(nil) } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 18, weight: .light))
                Text("Discover adhkar")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13))
            }
            .foregroundStyle(RoseryTheme.ink)
            .frame(minHeight: 56)
            .overlay(alignment: .top) { RoseryTheme.line.frame(height: 0.5) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var phrase: some View {
        Button { showSheet(.chooseDhikr) } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("YOUR TASBIH")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2.4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RoseryTheme.ink)
                }
                .foregroundStyle(RoseryTheme.muted)
                Text(store.selectedDhikr.arabic)
                    .font(RoseryTheme.arabic(46, relativeTo: .largeTitle))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .foregroundStyle(RoseryTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.selectedDhikr.subtitle)
                    .font(.system(.subheadline, weight: .regular))
                    .foregroundStyle(RoseryTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change dhikr, currently \(store.selectedDhikr.title)")
    }
}

struct CounterReadout: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var targetEditor: TargetEditingContext?
    var large = false

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        layout {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { CountInteraction.increment(store) }
            } label: {
                Text(String(format: "%02d", store.progress.count))
                    .font(.system(size: large ? 92 : 76, weight: .ultraLight, design: .rounded))
                    .tracking(-3)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(RoseryTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentShape(.rect)
            }
            .buttonStyle(CounterButtonStyle())
            .disabled(store.progress.isComplete)
            .accessibilityLabel("Count remembrance")
            .accessibilityValue("\(store.progress.count) of \(store.progress.target)")
            .accessibilityHint(store.progress.isComplete ? "Round complete" : "Double tap to add one")
            .accessibilityIdentifier(large ? "focus.count" : "tasbih.count")

            Button {
                store.refreshFromShared()
                targetEditor = TargetEditingContext(store: store)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text("Target \(store.progress.target.formatted())")
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(RoseryTheme.ink)
                    Text(store.isPersonalTarget ? "Personal target" : "Source count")
                        .font(.caption2)
                        .foregroundStyle(RoseryTheme.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change target")
            .accessibilityValue("\(store.progress.target), \(store.isPersonalTarget ? "personal target" : "source count")")
            .accessibilityHint("Choose a preset or enter a custom target. Increasing the target keeps your count.")
            .accessibilityIdentifier(large ? "focus.target" : "tasbih.target")
            .layoutPriority(1)
        }
        .frame(maxWidth: 390)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .sheet(item: $targetEditor) { context in
            TargetPickerView(context: context)
        }
    }
}

struct RoundCompletionView: View {
    @Environment(RoseryStore.self) private var store
    let openReading: (Dhikr) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let next = store.nextAfterPrayer {
                Button("Continue with \(next.title)") { store.beginNextAfterPrayer() }
                    .buttonStyle(PrimaryButtonStyle())
            } else if store.selectedDhikr.id == "allahu-akbar", !store.isPersonalTarget,
                      let completion = DhikrLibrary.reading(id: "tahlil") {
                Button("Read the hundredth remembrance") { openReading(completion) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Begin another round") { store.resetCounter() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
