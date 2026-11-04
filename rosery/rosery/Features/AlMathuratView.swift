import SwiftUI

struct AlMathuratView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RoseryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query: String
    @State private var selectedNumber: Int?
    @State private var showingEdition = false

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ROSERY_PREVIEW_MATHURAT"],
           let number = Int(raw), (1...28).contains(number) {
            _selectedNumber = State(initialValue: number)
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let usesSplit = geometry.size.width >= 800 && !dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 0) {
                header(isSplit: usesSplit)
                if let booklet = AlMathuratBooklet.bundled {
                    if usesSplit {
                        HStack(spacing: 0) {
                            contents(booklet, isSidebar: true)
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
                    ContentUnavailableView("Booklet unavailable", systemImage: "book.closed",
                                           description: Text("The Al-Mathurat reading file could not be loaded."))
                }
            }
        }
        .foregroundStyle(RoseryTheme.ink)
        .background(RoseryTheme.canvas)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingEdition) {
            if let booklet = AlMathuratBooklet.bundled { AlMathuratEditionView(booklet: booklet) }
        }
    }

    @ViewBuilder
    private func readingPane(_ booklet: AlMathuratBooklet, showsContents: Bool) -> some View {
        if let selectedNumber,
           let entry = booklet.entries.first(where: { $0.sourceItemNumber == selectedNumber }) {
            AlMathuratReadingView(entry: entry, total: booklet.entries.count,
                                 previous: { self.selectedNumber = selectedNumber - 1 },
                                 next: { self.selectedNumber = selectedNumber == booklet.entries.count ? nil : selectedNumber + 1 })
                .id(entry.id)
        } else if showsContents {
            contents(booklet)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("A daily wird")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                    Text("Al-Mathurat")
                        .font(.system(.largeTitle, weight: .semibold))
                        .tracking(-1.2)
                        .accessibilityAddTraits(.isHeader)
                    Text("المأثورات")
                        .font(RoseryTheme.arabic(32, relativeTo: .title))
                    Text("The complete sequence of 28 readings from the source booklet, in its original order.")
                        .font(.subheadline)
                        .foregroundStyle(RoseryTheme.muted)
                        .lineSpacing(4)
                    Button("Begin reading") { selectedNumber = 1 }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("mathurat.begin")
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
            if selectedNumber != nil && !isSplit {
                RoundIconButton(symbol: "list.bullet", label: "Al-Mathurat contents") { selectedNumber = nil }
                    .accessibilityIdentifier("mathurat.contents")
            } else {
                RoundIconButton(symbol: "chevron.down", label: "Close Al-Mathurat") { dismiss() }
            }
            if (selectedNumber != nil || isSplit) && !dynamicTypeSize.isAccessibilitySize {
                Text("Al-Mathurat")
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
            if selectedNumber != nil {
                RoundIconButton(symbol: "textformat.size", label: "Toggle larger Arabic text") {
                    store.updatePreferences { $0.largeArabic.toggle() }
                }
                if !isSplit {
                    RoundIconButton(symbol: "xmark", label: "Close Al-Mathurat") { dismiss() }
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

    private func contents(_ booklet: AlMathuratBooklet, isSidebar: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !isSidebar {
                    Text("A daily wird")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.bottom, 12)
                }
                Text(isSidebar ? "Contents" : "Al-Mathurat")
                    .font(.system(isSidebar ? .title2 : .largeTitle, weight: .semibold))
                    .tracking(-1.2)
                    .accessibilityAddTraits(.isHeader)
                if !isSidebar {
                    Text("المأثورات")
                        .font(RoseryTheme.arabic(32, relativeTo: .title))
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                    Text("The complete sequence of 28 readings from the source booklet, in its original order.")
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.bottom, 24)

                    Button { selectedNumber = 1 } label: {
                        HStack {
                            Text("Begin reading")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("mathurat.begin")
                    .padding(.bottom, 28)
                } else {
                    Text("\(booklet.entries.count) readings")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(RoseryTheme.muted)
                    TextField("Find a reading in Al-Mathurat", text: $query)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityLabel("Search Al-Mathurat")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Clear Al-Mathurat search")
                    }
                }
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) { RoseryTheme.line.frame(height: 0.5) }
                .padding(.bottom, 12)

                let entries = booklet.readings(matching: query)
                if entries.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Button { selectedNumber = entry.sourceItemNumber } label: {
                                AlMathuratRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSidebar && selectedNumber == entry.sourceItemNumber ? .isSelected : [])
                            .accessibilityIdentifier("mathurat.\(entry.id)")
                            .background(isSidebar && selectedNumber == entry.sourceItemNumber ? RoseryTheme.surface : .clear,
                                        in: .rect(cornerRadius: 8))
                            RoseryTheme.line.frame(height: 0.5)
                        }
                    }
                }
                Text("Repetition counts follow the booklet. Where it gives no count, none is assigned.")
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
}

private struct AlMathuratRow: View {
    let entry: AlMathuratBooklet.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(entry.sourceItemNumber, format: .number)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(RoseryTheme.muted)
                .frame(width: 22, alignment: .leading)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.title)
                    .font(.system(.body, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.repetitionLabel)
                    .font(.caption)
                    .foregroundStyle(RoseryTheme.muted)
                if entry.sourceItemNumber == 27 {
                    Text("Sunset only · booklet instruction")
                        .font(.caption)
                        .foregroundStyle(RoseryTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11))
                .foregroundStyle(RoseryTheme.muted)
                .padding(.top, 5)
        }
        .padding(.vertical, 18)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct AlMathuratReadingView: View {
    @Environment(RoseryStore.self) private var store
    @State private var showingSourceNotes = false
    let entry: AlMathuratBooklet.Entry
    let total: Int
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.passageLabel)
                        Spacer()
                        Text("\(entry.sourceItemNumber) / \(total)").monospacedDigit()
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

                VStack(spacing: 28) {
                    RoseryTheme.line.frame(height: 0.5)
                    ArabicText(text: entry.arabicNormalized, size: store.preferences.largeArabic ? 44 : 36,
                               alignment: entry.arabicNormalized.count < 90 ? .center : .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityIdentifier("mathurat.arabic")
                    RoseryTheme.line.frame(height: 0.5)
                }

                if store.preferences.transliteration {
                    VStack(alignment: .leading, spacing: 12) {
                        if let note = entry.transliterationNote { sourceNote(note) }
                        BookletTextSection(title: "Booklet transliteration", text: entry.transliteration)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let note = entry.meaningNote { sourceNote(note) }
                    BookletTextSection(title: "Meaning · booklet translation", text: entry.meaning)
                }
                BookletTextSection(title: "When to read · booklet instruction", text: entry.timingSource)
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

    private var navigation: some View {
        HStack(spacing: 14) {
            Button(action: previous) {
                Image(systemName: "arrow.left")
                    .frame(width: 52, height: 56)
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(RoseryTheme.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(entry.sourceItemNumber == 1)
            .opacity(entry.sourceItemNumber == 1 ? 0.3 : 1)
            .accessibilityLabel("Previous reading")
            .accessibilityIdentifier("mathurat.previous")
            Button(action: next) {
                HStack {
                    Text(entry.sourceItemNumber == total ? "Return to contents" : "Next reading")
                    Spacer(minLength: 8)
                    Image(systemName: entry.sourceItemNumber == total ? "list.bullet" : "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("mathurat.next")
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(RoseryTheme.canvas)
        .overlay(alignment: .top) { RoseryTheme.line.frame(height: 0.5) }
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Source")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(RoseryTheme.muted)
                .accessibilityAddTraits(.isHeader)
            Text("Al-Ma’thurat booklet · item \(entry.sourceItemNumber)\n\(entry.pageLabel)")
                .font(.subheadline)
                .lineSpacing(4)
            if entry.normalizationApplied {
                sourceNote("A documented spelling correction is applied to the Arabic. The printed text is preserved below.")
            }
            DisclosureGroup("Booklet text & source notes", isExpanded: $showingSourceNotes) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Arabic: \(AlMathuratBooklet.Entry.pageLabel(entry.pageReferences.arabic))\nTransliteration: \(AlMathuratBooklet.Entry.pageLabel(entry.pageReferences.transliteration))\nTranslation: \(AlMathuratBooklet.Entry.pageLabel(entry.pageReferences.translation))")
                        .font(.caption)
                        .lineSpacing(4)
                    Text(entry.repetitionSource + " " + entry.repetitionAuthority)
                        .font(.caption)
                        .lineSpacing(4)
                    ForEach(entry.editorialNotes, id: \.self) { note in sourceNote(note) }
                    if entry.normalizationApplied {
                        Text("Arabic as printed")
                            .font(.system(.caption, weight: .semibold))
                        ArabicText(text: entry.arabicSource, size: 28)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if entry.translationAligned != nil {
                        BookletTextSection(title: "Full English paragraph as printed", text: entry.translationSource)
                    }
                    if let address = entry.comparisonSource, let url = URL(string: address) {
                        Link(destination: url) {
                            Label("Editorial comparison reference", systemImage: "arrow.up.right")
                                .font(.subheadline)
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint("Opens a related source used for comparison; this reference is not printed in the booklet")
                    }
                }
                .padding(.top, 14)
            }
            .font(.subheadline)
            .tint(RoseryTheme.ink)
        }
    }

    private func sourceNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(RoseryTheme.muted)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AlMathuratEditionView: View {
    @Environment(\.dismiss) private var dismiss
    let booklet: AlMathuratBooklet

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
                    BookletTextSection(title: "The supplied booklet", text: "\(booklet.document.pdfPageCount) pages · \(booklet.document.numberedReadingCount) numbered readings\nCompiled by \(booklet.document.attributedCompiler)\nPrepared by \(booklet.document.preparedBy)")
                    BookletTextSection(title: "Reading text", text: "Arabic was checked against the booklet’s pages. Documented spelling corrections are identified with each reading. The English and transliteration retain the booklet’s wording; source differences are noted where they occur.")
                    BookletTextSection(title: "Counts & timing", text: "The booklet gives three repetitions for readings 6–24. It gives no count for readings 1–5 or 25–28. Counts and timing are attributed to this edition; the booklet does not provide individual hadith references. Several readings use morning wording, and Wird al-Rabitah is marked for sunset only.")
                    if let introduction = booklet.frontMatter.first(where: { $0.kind == "introduction" })?.sourceText {
                        BookletTextSection(title: "Introduction · as printed", text: introduction)
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

private struct BookletTextSection: View {
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
