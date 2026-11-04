import SwiftUI

struct DailyInvocationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RoseryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query: String
    @State private var selectedID: String?
    @State private var showingEdition = false

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["ROSERY_PREVIEW_DAILY_INVOCATIONS"],
           DailyInvocationsBooklet.bundled?.entries.contains(where: { $0.id == id }) == true {
            _selectedID = State(initialValue: id)
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let usesSplit = geometry.size.width >= 800 && !dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 0) {
                header(isSplit: usesSplit)
                if let booklet = DailyInvocationsBooklet.bundled {
                    if usesSplit {
                        HStack(spacing: 0) {
                            DailyInvocationsContents(booklet: booklet, query: $query,
                                                     select: { selectedID = $0 }, isSidebar: true,
                                                     selectedID: selectedID)
                                .frame(width: 280)
                            RoseryTheme.line.frame(width: 0.5)
                            readingPane(booklet, showsContents: false)
                        }
                        .frame(maxWidth: 1040)
                        .frame(maxWidth: .infinity)
                    } else {
                        readingPane(booklet, showsContents: true)
                    }
                } else {
                    ContentUnavailableView("Readings unavailable", systemImage: "book.closed",
                                           description: Text("The daily invocations reading file could not be loaded."))
                }
            }
        }
        .foregroundStyle(RoseryTheme.ink)
        .background(RoseryTheme.canvas)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingEdition) {
            if let booklet = DailyInvocationsBooklet.bundled {
                DailyInvocationsEditionView(document: booklet.document)
            }
        }
    }

    @ViewBuilder
    private func readingPane(_ booklet: DailyInvocationsBooklet, showsContents: Bool) -> some View {
        if let entry = booklet.entries.first(where: { $0.id == selectedID }) {
            DailyInvocationReadingView(entry: entry, document: booklet.document,
                                       total: booklet.entries.count,
                                       previous: { select(entry.order - 1, in: booklet) },
                                       next: { select(entry.order + 1, in: booklet) })
                .id(entry.id)
        } else if showsContents {
            DailyInvocationsContents(booklet: booklet, query: $query, select: { selectedID = $0 })
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(booklet.document.sourceTitle)
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                    Text(booklet.document.title)
                        .font(.system(.largeTitle, weight: .semibold))
                        .tracking(-1.2)
                        .accessibilityAddTraits(.isHeader)
                    Text(booklet.document.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(RoseryTheme.muted)
                        .lineSpacing(4)
                    if let first = booklet.entries.first {
                        Button("Begin reading") { selectedID = first.id }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("daily-invocations.begin")
                    }
                }
                .padding(26)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func header(isSplit: Bool) -> some View {
        HStack(spacing: 8) {
            if selectedID != nil && !isSplit {
                RoundIconButton(symbol: "list.bullet", label: "Daily invocations contents") { selectedID = nil }
                    .accessibilityIdentifier("daily-invocations.contents")
            } else {
                RoundIconButton(symbol: "chevron.down", label: "Close daily invocations") { dismiss() }
            }
            if (selectedID != nil || isSplit) && !dynamicTypeSize.isAccessibilitySize {
                Text("Daily invocations")
                    .font(.system(.subheadline, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isSplit {
                Button("About this edition") { showingEdition = true }
                    .font(.caption)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
            }
            if selectedID != nil {
                RoundIconButton(symbol: "textformat.size", label: "Toggle larger Arabic text") {
                    store.updatePreferences { $0.largeArabic.toggle() }
                }
                .accessibilityIdentifier("daily-invocations.text-size")
                if !isSplit {
                    RoundIconButton(symbol: "xmark", label: "Close daily invocations") { dismiss() }
                }
            } else if !isSplit {
                Button("About this edition") { showingEdition = true }
                    .font(.caption)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: isSplit ? 1040 : 680)
        .frame(maxWidth: .infinity)
    }

    private func select(_ order: Int, in booklet: DailyInvocationsBooklet) {
        selectedID = booklet.entries.first { $0.order == order }?.id
    }
}

private struct DailyInvocationsContents: View {
    let booklet: DailyInvocationsBooklet
    @Binding var query: String
    let select: (String) -> Void
    var isSidebar = false
    var selectedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !isSidebar {
                    Text("\(booklet.document.sourceTitle) · \(booklet.document.pageLabel.lowercased())")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.bottom, 12)
                }
                Text(isSidebar ? "Contents" : booklet.document.title)
                    .font(.system(isSidebar ? .title2 : .largeTitle, weight: .semibold))
                    .tracking(-1.2)
                    .accessibilityAddTraits(.isHeader)
                if !isSidebar {
                    Text(booklet.document.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(RoseryTheme.muted)
                        .lineSpacing(4)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    if let first = booklet.entries.first {
                        Button { select(first.id) } label: {
                            HStack {
                                Text("Begin reading")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("daily-invocations.begin")
                        .padding(.bottom, 28)
                    }
                } else {
                    Text("\(booklet.entries.count) readings")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }

                searchField
                    .padding(.bottom, 20)

                let sections = booklet.sections(matching: query)
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(section.title)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .accessibilityAddTraits(.isHeader)
                                    .padding(.bottom, 8)
                                ForEach(section.entries) { entry in
                                    DailyInvocationRow(entry: entry, isSelected: isSidebar && selectedID == entry.id) {
                                        select(entry.id)
                                    }
                                }
                            }
                        }
                    }
                }

                Text("Practices and counts follow the photographed source. An unspecified count remains unspecified.")
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
                    .lineSpacing(4)
                    .padding(.top, 24)
            }
            .padding(.horizontal, isSidebar ? 18 : 26)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RoseryTheme.muted)
            TextField("Find a daily invocation", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel("Search daily invocations")
                .accessibilityIdentifier("daily-invocations.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear daily invocations search")
            }
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { RoseryTheme.line.frame(height: 0.5) }
    }
}

private struct DailyInvocationRow: View {
    let entry: DailyInvocationsBooklet.Entry
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Text(entry.order, format: .number)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(RoseryTheme.muted)
                    .frame(width: 25, alignment: .leading)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.title)
                        .font(.system(.body, weight: .medium))
                    Text(entry.repetitionLabel)
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(RoseryTheme.muted)
                    .padding(.top, 5)
            }
            .padding(.vertical, 18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("daily-invocations.\(entry.id)")
        .background(isSelected ? RoseryTheme.surface : .clear, in: .rect(cornerRadius: 8))
        .overlay(alignment: .bottom) { RoseryTheme.line.frame(height: 0.5) }
    }
}

private struct DailyInvocationReadingView: View {
    @Environment(RoseryStore.self) private var store
    @State private var showingSourceNotes = false
    let entry: DailyInvocationsBooklet.Entry
    let document: DailyInvocationsBooklet.Document
    let total: Int
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.section)
                        Spacer(minLength: 12)
                        Text("\(entry.order) / \(total)").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
                    Text(entry.title)
                        .font(.system(.largeTitle, weight: .semibold))
                        .tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(entry.repetitionLabel)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(RoseryTheme.muted)
                }

                if let note = entry.readingNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Source note. \(note)")
                }

                if let arabic = entry.arabic {
                    VStack(spacing: 28) {
                        RoseryTheme.line.frame(height: 0.5)
                        ArabicText(text: arabic, size: store.preferences.largeArabic ? 44 : 36,
                                   alignment: arabic.count < 90 ? .center : .trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("daily-invocations.arabic")
                        RoseryTheme.line.frame(height: 0.5)
                    }
                }

                if let text = entry.transliteration,
                   store.preferences.transliteration || entry.arabic == nil {
                    DailyInvocationTextSection(title: "Source transliteration", text: text)
                }
                if let text = entry.translation {
                    DailyInvocationTextSection(title: "Meaning · source translation", text: text)
                }
                if !entry.practice.isEmpty {
                    DailyInvocationTextSection(title: "Practice · source instruction", text: entry.practice)
                }
                sourceDetails
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { navigation }
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Source")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(RoseryTheme.muted)
                .accessibilityAddTraits(.isHeader)
            Text("\(document.sourceTitle)\n\(entry.pageLabel)")
                .font(.subheadline)
                .lineSpacing(4)
            if let part = entry.sourcePart {
                Text(part)
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
            }
            if let label = entry.footnoteLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
            }
            DisclosureGroup("Source heading & notes", isExpanded: $showingSourceNotes) {
                VStack(alignment: .leading, spacing: 16) {
                    DailyInvocationTextSection(title: "Heading as printed", text: entry.sourceHeading)
                    Text("Practice wording and repetition counts are attributed to this source edition.")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                    ForEach(entry.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(RoseryTheme.muted)
                            .lineSpacing(4)
                    }
                }
                .padding(.top, 14)
            }
            .font(.subheadline)
            .tint(RoseryTheme.ink)
        }
    }

    private var navigation: some View {
        HStack(spacing: 14) {
            Button(action: previous) {
                Image(systemName: "arrow.left")
                    .frame(width: 52, height: 56)
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(RoseryTheme.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(entry.order == 1)
            .opacity(entry.order == 1 ? 0.3 : 1)
            .accessibilityLabel("Previous invocation")
            .accessibilityIdentifier("daily-invocations.previous")
            Button(action: next) {
                HStack {
                    Text(entry.order == total ? "Return to contents" : "Next invocation")
                    Spacer(minLength: 8)
                    Image(systemName: entry.order == total ? "list.bullet" : "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("daily-invocations.next")
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(RoseryTheme.canvas)
        .overlay(alignment: .top) { RoseryTheme.line.frame(height: 0.5) }
    }
}

private struct DailyInvocationsEditionView: View {
    @Environment(\.dismiss) private var dismiss
    let document: DailyInvocationsBooklet.Document

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RoundIconButton(symbol: "chevron.down", label: "Close edition details") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("About this edition")
                        .font(.system(.largeTitle, weight: .semibold))
                        .tracking(-1.2)
                        .accessibilityAddTraits(.isHeader)
                    DailyInvocationTextSection(title: document.sourceTitle,
                                               text: "\(document.pageLabel) · \(document.photoCount) supplied photographs\n\(document.subtitle)")
                    ForEach(document.notes, id: \.self) { note in
                        Text(note)
                            .font(.body)
                            .lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(RoseryTheme.ink)
        .background(RoseryTheme.canvas)
        .presentationDragIndicator(.visible)
    }
}

private struct DailyInvocationTextSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(RoseryTheme.muted)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(.body, design: .serif))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
