import SwiftUI

struct SavedView: View {
    @Environment(RoseryStore.self) private var store
    let openReading: (Dhikr) -> Void
    let openLibrary: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Saved")
                        .font(.system(size: 38, weight: .semibold))
                        .tracking(-1.8)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("YOUR COLLECTION")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(RoseryTheme.muted)
                }
                .padding(.bottom, 30)

                if store.bookmarks.isEmpty {
                    emptyBookmarks
                } else {
                    HStack {
                        Text("Bookmarked readings")
                            .font(.system(.subheadline, weight: .medium))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text(store.bookmarks.count, format: .number)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(RoseryTheme.muted)
                    }
                    .padding(.bottom, 8)

                    LazyVStack(spacing: 0) {
                        ForEach(store.bookmarks) { dhikr in
                            ReadingRow(dhikr: dhikr) { openReading(dhikr) }
                            RoseryTheme.line.frame(height: 0.5)
                        }
                    }
                }

                if !store.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Recent rounds")
                            .font(.system(.title3, weight: .medium))
                            .tracking(-0.5)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 14)

                        ForEach(store.sessions.prefix(5)) { session in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(DhikrLibrary.reading(id: session.dhikrID)?.title ?? "Dhikr")
                                        .font(.system(.subheadline, weight: .medium))
                                    Text(session.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(RoseryTheme.muted)
                                }
                                Spacer()
                                Text(session.count, format: .number)
                                    .font(.system(size: 28, weight: .light, design: .rounded))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 17)
                            .accessibilityElement(children: .combine)
                            RoseryTheme.line.frame(height: 0.5)
                        }
                    }
                    .padding(.top, 38)
                }

                Text("Kept on this device, just for you.")
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
                    .padding(.top, 30)
            }
            .foregroundStyle(RoseryTheme.ink)
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyBookmarks: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoseryTheme.line.frame(height: 0.5)
            Image(systemName: "bookmark")
                .font(.system(size: 32, weight: .ultraLight))
                .padding(.top, 36)
                .padding(.bottom, 24)
                .accessibilityHidden(true)
            Text("Keep the words\nyou return to.")
                .font(.system(size: 28, weight: .medium))
                .tracking(-0.9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            Text("Bookmark a reading in the library.\nFind it here whenever you need it.")
                .font(.subheadline)
                .lineSpacing(5)
                .foregroundStyle(RoseryTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            Button(action: openLibrary) {
                HStack(spacing: 12) {
                    Text("Explore the library")
                        .font(.system(.subheadline, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
            RoseryTheme.line.frame(height: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
