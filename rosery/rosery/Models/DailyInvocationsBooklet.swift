import Foundation

/// A separate source edition; its printed practices do not alter tasbih targets.
nonisolated struct DailyInvocationsBooklet: Decodable, Sendable {
    let schemaVersion: Int
    let document: Document
    let entries: [Entry]

    nonisolated struct Document: Decodable, Sendable {
        let title: String
        let sourceTitle: String
        let subtitle: String
        let firstPage: Int
        let lastPage: Int
        let photoCount: Int
        let notes: [String]

        var pageLabel: String { "Printed pages \(firstPage)–\(lastPage)" }
    }

    nonisolated struct Entry: Decodable, Identifiable, Sendable {
        let id: String
        let order: Int
        let section: String
        let sourceHeading: String
        let title: String
        let arabic: String?
        let transliteration: String?
        let translation: String?
        let practice: String
        let repetitions: Int?
        let repetitionGuidance: String?
        let sourcePages: [Int]
        let sourceFootnotes: [Int]
        let sourcePart: String?
        let readingNote: String?
        let notes: [String]

        var repetitionLabel: String {
            if let repetitionGuidance { return repetitionGuidance }
            if arabic == nil && transliteration == nil && repetitions == nil { return "Reading guidance" }
            return repetitions.map { "\($0) \($0 == 1 ? "time" : "times") in source" } ?? "Count not specified"
        }

        var pageLabel: String {
            let numbers = sourcePages.map(String.init).joined(separator: ", ")
            return "Printed \(sourcePages.count == 1 ? "page" : "pages") \(numbers)"
        }

        var footnoteLabel: String? {
            guard !sourceFootnotes.isEmpty else { return nil }
            let numbers = sourceFootnotes.map(String.init).joined(separator: ", ")
            return "Printed \(sourceFootnotes.count == 1 ? "footnote" : "footnotes") \(numbers)"
        }

        func matches(_ query: String) -> Bool {
            let text = [title, section, sourceHeading, arabic ?? "", transliteration ?? "", translation ?? "",
                        practice, pageLabel, footnoteLabel ?? "", sourcePart ?? "", repetitionLabel, readingNote ?? ""] + notes
            return DailyInvocationsBooklet.search(text.joined(separator: " "), contains: query)
        }
    }

    nonisolated struct Section: Identifiable, Sendable {
        let id: String
        let title: String
        var entries: [Entry]
    }

    enum LoadingError: Error {
        case missingResource, invalidEdition
    }

    static let bundled: DailyInvocationsBooklet? = try? load()

    static func load(from url: URL? = Bundle.main.url(forResource: "daily-invocations", withExtension: "json")) throws -> Self {
        guard let url else { throw LoadingError.missingResource }
        let booklet = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        let document = booklet.document
        guard booklet.schemaVersion == 1,
              [document.title, document.sourceTitle, document.subtitle].allSatisfy(nonblank),
              document.firstPage > 0, document.lastPage >= document.firstPage, document.photoCount > 0,
              !booklet.entries.isEmpty,
              booklet.entries.map(\.order) == Array(1...booklet.entries.count),
              Set(booklet.entries.map(\.id)).count == booklet.entries.count,
              booklet.entries.allSatisfy({ entry in
                  [entry.id, entry.title, entry.section, entry.sourceHeading].allSatisfy(nonblank) &&
                  (entry.arabic.map { nonblank($0) && !containsPrivateUseGlyphs($0) } ?? true) &&
                  (entry.arabic != nil || nonblank(entry.practice)) &&
                  (entry.transliteration.map(nonblank) ?? true) &&
                  (entry.translation.map(nonblank) ?? true) &&
                  (entry.readingNote.map(nonblank) ?? true) &&
                  (entry.sourcePart.map(nonblank) ?? true) &&
                  (entry.repetitionGuidance.map(nonblank) ?? true) &&
                  (entry.repetitions.map { $0 > 0 } ?? true) &&
                  (entry.repetitions == nil || entry.repetitionGuidance == nil) &&
                  !entry.sourcePages.isEmpty &&
                  entry.sourcePages == Array(Set(entry.sourcePages)).sorted() &&
                  entry.sourcePages.allSatisfy { (document.firstPage...document.lastPage).contains($0) } &&
                  entry.sourceFootnotes == Array(Set(entry.sourceFootnotes)).sorted() &&
                  entry.sourceFootnotes.allSatisfy { $0 > 0 }
              }) else { throw LoadingError.invalidEdition }
        return booklet
    }

    func matches(_ query: String) -> Bool {
        matchesDocument(query) || entries.contains { $0.matches(query) }
    }

    func readings(matching query: String) -> [Entry] {
        matchesDocument(query) ? entries : entries.filter { $0.matches(query) }
    }

    /// Groups consecutive readings without changing the printed order.
    func sections(matching query: String) -> [Section] {
        var sections: [Section] = []
        for entry in readings(matching: query) {
            if sections.last?.title == entry.section {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(Section(id: entry.id, title: entry.section, entries: [entry]))
            }
        }
        return sections
    }

    private func matchesDocument(_ query: String) -> Bool {
        let text = [document.title, document.sourceTitle, document.subtitle, document.pageLabel,
                    "Daily invocations الدعوات اليومية"] + document.notes
        return Self.search(text.joined(separator: " "), contains: query)
    }

    private static func nonblank(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func containsPrivateUseGlyphs(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0xE000...0xF8FF).contains(scalar.value) ||
            (0xF0000...0xFFFFD).contains(scalar.value) || (0x100000...0x10FFFD).contains(scalar.value)
        }
    }

    private static func search(_ text: String, contains query: String) -> Bool {
        let normalizedQuery = normalizedForSearch(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return normalizedQuery.isEmpty || normalizedForSearch(text).contains(normalizedQuery)
    }

    private static func normalizedForSearch(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) && $0.value != 0x0640 }
        return String(String.UnicodeScalarView(scalars))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ٱ", with: "ا")
    }
}
