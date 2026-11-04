import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct TasbihLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TasbihActivityAttributes.self) { context in
            TasbihLiveActivityCard(
                attributes: context.attributes, state: context.state, isStale: context.isStale
            )
            .widgetURL(TasbihLiveActivityPresentation.openURL)
        } dynamicIsland: { context in
            let presentation = TasbihLiveActivityPresentation(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        TasbihActivityProgressMark(presentation: presentation)
                            .frame(width: 22, height: 22)
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(TasbihLiveActivityPresentation.islandInk)
                    .accessibilityLabel(context.state.title)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TasbihActivityReadout(state: context.state, compact: true)
                        .foregroundStyle(TasbihLiveActivityPresentation.islandInk)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ProgressView(value: presentation.progress)
                            .progressViewStyle(.linear)
                            .frame(height: 4)
                            .tint(TasbihLiveActivityPresentation.islandInk)
                            .accessibilityHidden(true)
                        TasbihActivityActions(
                            attributes: context.attributes, presentation: presentation,
                            ink: TasbihLiveActivityPresentation.islandInk, canvas: .black
                        )
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                TasbihActivityProgressMark(presentation: presentation)
                    .foregroundStyle(TasbihLiveActivityPresentation.islandInk)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(presentation.accessibilitySummary)
            } compactTrailing: {
                Text(context.state.count, format: .number.grouping(.never))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: 46)
                    .foregroundStyle(TasbihLiveActivityPresentation.islandInk)
                    .accessibilityLabel(presentation.accessibilitySummary)
            } minimal: {
                TasbihActivityProgressMark(presentation: presentation)
                    .foregroundStyle(TasbihLiveActivityPresentation.islandInk)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(presentation.accessibilitySummary)
            }
            .widgetURL(TasbihLiveActivityPresentation.openURL)
            .keylineTint(TasbihLiveActivityPresentation.islandInk)
        }
    }
}

struct TasbihLiveActivityPresentation {
    let state: TasbihActivityAttributes.ContentState
    let isStale: Bool

    static let openURL = URL(string: "rosery://tasbih")!
    static let islandInk = Color(red: 0.95, green: 0.95, blue: 0.91)

    var canCount: Bool {
        !isStale && state.phase == .counting && state.count >= 0 && state.count < state.target
    }

    var progress: Double {
        min(1, max(0, Double(state.count) / Double(max(1, state.target))))
    }

    var status: String {
        switch state.phase {
        case .complete: "Round complete"
        case .ended: "Session ended"
        case .counting: isStale ? "Open to refresh" : (state.count >= state.target ? "Round complete" : "Counting")
        }
    }

    var statusSymbol: String? {
        switch state.phase {
        case .complete: "checkmark"
        case .ended: "stop.fill"
        case .counting: isStale ? "arrow.clockwise" : (state.count >= state.target ? "checkmark" : nil)
        }
    }

    var accessibilitySummary: String {
        "\(state.title), \(state.count) of \(state.target). \(status)."
    }
}

struct TasbihLiveActivityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var titleSize = 12.0

    let attributes: TasbihActivityAttributes
    let state: TasbihActivityAttributes.ContentState
    let isStale: Bool

    private var presentation: TasbihLiveActivityPresentation {
        .init(state: state, isStale: isStale)
    }

    private var ink: Color {
        colorScheme == .dark
            ? TasbihLiveActivityPresentation.islandInk
            : Color(red: 0.14, green: 0.16, blue: 0.14)
    }

    private var canvas: Color {
        colorScheme == .dark
            ? Color(red: 0.085, green: 0.098, blue: 0.09)
            : Color(red: 0.969, green: 0.969, blue: 0.949)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(state.arabic)
                            .font(.custom("NotoNaskhArabic-Regular", fixedSize: 25))
                            .environment(\.layoutDirection, .rightToLeft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .accessibilityHidden(true)
                    }
                    Text(state.title)
                        .font(.system(size: min(titleSize, 19), weight: .medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(ink.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TasbihActivityReadout(state: state, compact: false)
                    .frame(maxWidth: 122, alignment: .trailing)
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilitySummary)

            ProgressView(value: presentation.progress)
                .progressViewStyle(.linear)
                .frame(height: 4)
                .tint(ink)
                .accessibilityHidden(true)

            TasbihActivityActions(attributes: attributes, presentation: presentation, ink: ink, canvas: canvas)
        }
        .padding(14)
        .foregroundStyle(ink)
        .activityBackgroundTint(canvas)
        .activitySystemActionForegroundColor(ink)
    }
}

struct TasbihActivityReadout: View {
    @ScaledMetric(relativeTo: .title) private var countSize = 30.0
    @ScaledMetric(relativeTo: .caption2) private var targetSize = 11.0
    let state: TasbihActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(state.count, format: .number.grouping(.never))
                .font(.system(size: compact ? 25 : min(countSize, 38), weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("of \(state.target)")
                .font(.system(size: compact ? 11 : min(targetSize, 15), weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.count) of \(state.target)")
    }
}

struct TasbihActivityActions: View {
    @ScaledMetric(relativeTo: .callout) private var labelSize = 14.0
    let attributes: TasbihActivityAttributes
    let presentation: TasbihLiveActivityPresentation
    let ink: Color
    let canvas: Color

    var body: some View {
        Group {
            if presentation.canCount {
                HStack(spacing: 8) {
                    Button(intent: IncrementTasbihLiveActivityIntent(expectedID: attributes.selectedID, generation: attributes.generation)) {
                        Text("+1")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(canvas)
                            .background(ink, in: .capsule)
                    }
                    .accessibilityLabel("Add one remembrance")
                    .accessibilityValue("\(presentation.state.count) of \(presentation.state.target)")

                    Button(intent: UndoTasbihLiveActivityIntent(expectedID: attributes.selectedID, generation: attributes.generation)) {
                        actionLabel("Undo", symbol: "arrow.uturn.backward")
                    }
                    .disabled(presentation.state.count == 0)
                    .opacity(presentation.state.count == 0 ? 0.45 : 1)
                    .accessibilityLabel("Undo last count")

                    Button(intent: StopTasbihLiveActivityIntent(expectedID: attributes.selectedID, generation: attributes.generation)) {
                        actionLabel("End", symbol: "stop")
                    }
                    .accessibilityLabel("End Live Activity")
                    .accessibilityHint("Keeps your count in Rosery.")
                }
            } else {
                HStack(spacing: 10) {
                    Text(presentation.status)
                        .foregroundStyle(ink.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Link(destination: TasbihLiveActivityPresentation.openURL) {
                        Label("Open Rosery", systemImage: "arrow.up.right")
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .foregroundStyle(canvas)
                            .background(ink, in: .capsule)
                    }
                    .accessibilityLabel("Open Rosery")
                    .accessibilityHint("Returns to your current tasbih.")
                }
            }
        }
        .font(.system(size: min(labelSize, 19), weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .buttonStyle(.plain)
        .foregroundStyle(ink)
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleOnly)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ink.opacity(0.1), in: .capsule)
    }
}

struct TasbihActivityProgressMark: View {
    let presentation: TasbihLiveActivityPresentation

    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 2)
            if let symbol = presentation.statusSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            } else {
                Circle()
                    .trim(from: 0, to: presentation.progress)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
                Circle().fill().frame(width: 4, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}
