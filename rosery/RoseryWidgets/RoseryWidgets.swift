import SwiftUI
import WidgetKit

@main
struct RoseryWidgetBundle: WidgetBundle {
    var body: some Widget {
        RoseryTasbihWidget()
        TasbihLiveActivityWidget()
    }
}

struct RoseryTasbihWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TasbihShared.widgetKind, provider: TasbihTimelineProvider()) { entry in
            TasbihWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Your tasbih")
        .description("Keep your remembrance close. Tap to count the dhikr selected in Rosery.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TasbihWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TasbihSnapshot
}

struct TasbihTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasbihWidgetEntry {
        TasbihWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasbihWidgetEntry) -> Void) {
        completion(TasbihWidgetEntry(date: .now, snapshot: context.isPreview ? .preview : readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasbihWidgetEntry>) -> Void) {
        let entry = TasbihWidgetEntry(date: .now, snapshot: readSnapshot())
        // Counts have no time-based changes. App writes and widget interactions request new snapshots.
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readSnapshot() -> TasbihSnapshot {
        (try? TasbihRepository.appGroup().snapshot()) ?? .needsApp
    }
}

#Preview(as: .systemSmall) {
    RoseryTasbihWidget()
} timeline: {
    TasbihWidgetEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    RoseryTasbihWidget()
} timeline: {
    TasbihWidgetEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemLarge) {
    RoseryTasbihWidget()
} timeline: {
    TasbihWidgetEntry(date: .now, snapshot: .preview)
}

#Preview(as: .accessoryRectangular) {
    RoseryTasbihWidget()
} timeline: {
    TasbihWidgetEntry(date: .now, snapshot: .preview)
}
