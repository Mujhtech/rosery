import SwiftUI

struct LibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var collection: DhikrCollection?
    @State private var query = ""
    let openReading: (Dhikr) -> Void
    let openMathurat: (String) -> Void
    let openDailyInvocations: (String) -> Void

    private var results: [Dhikr] {
        (collection?.readings ?? DhikrLibrary.readings).filter { $0.matches(query) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                contents(usesColumns: geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
    }

    private func contents(usesColumns: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(.system(size: 38, weight: .semibold))
                    .tracking(-1.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("QUR’AN & ADHKAR")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(RoseryTheme.muted)
            }
            .padding(.bottom, 22)

            searchField
                .padding(.bottom, 12)
            filters
                .padding(.bottom, 26)

            if showsSourceCollection {
                let columns = Array(repeating: GridItem(.flexible(), alignment: .top),
                                    count: usesColumns && showsMathurat && showsDailyInvocations ? 2 : 1)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    if showsMathurat { mathuratCollection }
                    if showsDailyInvocations { dailyInvocationsCollection }
                }
                .padding(.bottom, 28)
            }

            VStack(alignment: .leading, spacing: 0) {
                if !results.isEmpty || !showsSourceCollection {
                    HStack(alignment: .firstTextBaseline) {
                        Text(collection?.title ?? "Individual readings")
                            .font(.system(.subheadline, weight: .medium))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text(results.count, format: .number)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(RoseryTheme.muted)
                    }
                    .padding(.bottom, 8)
                }

                if results.isEmpty && !showsSourceCollection {
                    ContentUnavailableView.search(text: query)
                        .foregroundStyle(RoseryTheme.muted)
                    if collection != nil {
                        Button { collection = nil } label: {
                            Text("Search all collections")
                                .font(.system(.subheadline, weight: .medium))
                                .underline()
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { dhikr in
                            ReadingRow(dhikr: dhikr) { openReading(dhikr) }
                            RoseryTheme.line.frame(height: 0.5)
                        }
                    }
                }

                Text("Each reading includes its source.")
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
                    .padding(.top, 26)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(RoseryTheme.ink)
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 30)
        .frame(maxWidth: 1040)
        .frame(maxWidth: .infinity)
    }

    private var showsMathurat: Bool {
        (collection == nil || collection == .morning || collection == .evening) &&
        (AlMathuratBooklet.bundled?.matches(query) ?? query.isEmpty)
    }

    private var showsDailyInvocations: Bool {
        collection == nil && (DailyInvocationsBooklet.bundled?.matches(query) ?? query.isEmpty)
    }

    private var showsSourceCollection: Bool { showsMathurat || showsDailyInvocations }

    private var dailyInvocationsCollection: some View {
        Button { openDailyInvocations(query) } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REMEMBRANCE THROUGH THE DAY")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(RoseryTheme.muted)
                    Text("Daily invocations")
                        .font(.system(.title2, weight: .semibold))
                        .tracking(-0.5)
                    Text(DailyInvocationsBooklet.bundled.map {
                        "\($0.document.sourceTitle) · \($0.document.pageLabel.lowercased())"
                    } ?? "Photographed source edition")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .regular))
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .background(RoseryTheme.surface, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(RoseryTheme.line, lineWidth: 0.5) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.daily-invocations")
    }

    private var mathuratCollection: some View {
        Button { openMathurat(query) } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("THE COMPLETE WIRD")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(RoseryTheme.muted)
                    Text("Al-Mathurat")
                        .font(.system(.title2, weight: .semibold))
                        .tracking(-0.5)
                    Text("28 readings · in booklet order")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .regular))
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .background(RoseryTheme.surface, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(RoseryTheme.line, lineWidth: 0.5) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.al-mathurat")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(RoseryTheme.muted)
            TextField("Search a dhikr or verse", text: $query)
                .font(.subheadline)
                .foregroundStyle(RoseryTheme.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search readings")
                .accessibilityIdentifier("library.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RoseryTheme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { RoseryTheme.line.frame(height: 0.5) }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                CollectionTab(title: "All", isSelected: collection == nil) { collection = nil }
                ForEach(DhikrCollection.allCases) { item in
                    CollectionTab(title: item.shortTitle, isSelected: collection == item) { collection = item }
                }
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { RoseryTheme.line.frame(height: 0.5) }
    }
}

private struct CollectionTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? RoseryTheme.ink : RoseryTheme.muted)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        RoseryTheme.ink.frame(height: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ReadingRow: View {
    @Environment(RoseryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let dhikr: Dhikr
    let action: () -> Void

    private var hasCompactArabic: Bool {
        dhikr.arabic.count <= 36 && !dhikr.arabic.contains("\n")
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dhikr.title)
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(RoseryTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dhikr.subtitle)
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !hasCompactArabic || dynamicTypeSize.isAccessibilitySize {
                        Text(dhikr.repetitionLabel)
                            .font(.caption2)
                            .foregroundStyle(RoseryTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasCompactArabic && !dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(dhikr.arabic)
                            .font(RoseryTheme.arabic(28, relativeTo: .title2))
                            .foregroundStyle(RoseryTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text(dhikr.repetitionLabel)
                            .font(.caption2)
                            .foregroundStyle(RoseryTheme.muted)
                    }
                    .frame(maxWidth: 142, alignment: .trailing)
                }

                Image(systemName: store.isBookmarked(dhikr) ? "bookmark.fill" : "arrow.up.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(RoseryTheme.muted)
                    .frame(width: 12)
            }
            .frame(minHeight: 66)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reading.\(dhikr.id)")
    }
}
