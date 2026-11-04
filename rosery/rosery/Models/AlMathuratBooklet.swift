import Foundation

/// This edition remains separate from the individually sourced DhikrLibrary readings.
nonisolated struct AlMathuratBooklet: Decodable, Sendable {
    let schemaVersion: Int
    let document: Document
    let frontMatter: [FrontMatter]
    let entries: [Entry]

    nonisolated struct Document: Decodable, Sendable {
        let title: String
        let attributedCompiler: String
        let preparedBy: String
        let pdfPageCount: Int
        let numberedReadingCount: Int
    }

    nonisolated struct FrontMatter: Decodable, Sendable {
        let kind: String
        let sourceText: String?
    }

    nonisolated struct PageReferences: Decodable, Sendable {
        let arabic: [Int]
        let transliteration: [Int]
        let translation: [Int]
    }

    nonisolated struct Entry: Decodable, Identifiable, Sendable {
        let id: String
        let sourceItemNumber: Int
        let title: String
        let arabicSource: String
        let arabicNormalized: String
        let normalizationApplied: Bool
        let transliteration: String
        let translation: String
        let transliterationSource: String
        let translationSource: String
        let translationAligned: String?
        let translationAlignmentNote: String?
        let repetitions: Int?
        let repetitionSource: String
        let repetitionAuthority: String
        let timingSource: String
        let kind: String
        let quranReference: String?
        let sourcePages: [Int]
        let pageReferences: PageReferences
        let editorialNotes: [String]
        let comparisonSource: String?

        var meaning: String { translationAligned ?? translation }
        var meaningNote: String? {
            guard translationAligned != nil else { return nil }
            return "The booklet includes a separate sunset prayer and closing words that are absent from this Arabic passage. They are omitted here; the full English paragraph is preserved in the source notes."
        }
        var repetitionLabel: String {
            repetitions.map { "\($0) times in booklet" } ?? "Count not specified"
        }
        var passageLabel: String {
            if let quranReference { return "Qur’an \(quranReference)" }
            return kind == "compiled-devotional-prayer" ? "Devotional prayer" : "Dhikr & du’a"
        }
        var pageLabel: String { Self.pageLabel(sourcePages) }
        var transliterationNote: String? {
            switch sourceItemNumber {
            case 1: "The booklet’s transliteration ends “Rajeen”; the Arabic reads ar-rajim."
            case 25: "The booklet’s transliteration omits sayyidina, which appears in the Arabic."
            case 27: "The printed transliteration differs from the Arabic in several places. See the source notes before using it as a pronunciation aid."
            case 28: "The booklet prints “Nabiyyin”; the Arabic reads nabiyyina (our Prophet)."
            default: nil
            }
        }

        func matches(_ query: String) -> Bool {
            let text = [title, arabicNormalized, transliteration, meaning, quranReference ?? ""].joined(separator: " ")
            return AlMathuratBooklet.search(text, contains: query)
        }

        static func pageLabel(_ pages: [Int]) -> String {
            let numbers = pages.map(String.init).joined(separator: ", ")
            return pages.count == 1 ? "PDF page \(numbers)" : "PDF pages \(numbers)"
        }
    }

    enum LoadingError: Error {
        case missingResource, invalidEdition
    }

    static let bundled: AlMathuratBooklet? = try? load()

    static func load(from url: URL? = Bundle.main.url(forResource: "al-mathurat", withExtension: "json")) throws -> AlMathuratBooklet {
        guard let url else { throw LoadingError.missingResource }
        let booklet = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard booklet.schemaVersion == 1,
              booklet.document.numberedReadingCount == 28,
              booklet.entries.map(\.sourceItemNumber) == Array(1...28),
              Set(booklet.entries.map(\.id)).count == 28,
              booklet.entries.allSatisfy({ entry in
                  !entry.arabicNormalized.isEmpty && !entry.transliteration.isEmpty && !entry.meaning.isEmpty &&
                  (entry.repetitions.map { $0 > 0 } ?? true) &&
                  !entry.sourcePages.isEmpty && entry.sourcePages.allSatisfy { (1...booklet.document.pdfPageCount).contains($0) }
              }) else { throw LoadingError.invalidEdition }
        return booklet
    }

    func matches(_ query: String) -> Bool {
        Self.search("Al-Mathurat Al-Ma’thurat Mathurat المأثورات", contains: query) || entries.contains { $0.matches(query) }
    }

    func readings(matching query: String) -> [Entry] {
        if Self.search("Al-Mathurat Al-Ma’thurat Mathurat المأثورات", contains: query) { return entries }
        return entries.filter { $0.matches(query) }
    }

    private static func search(_ text: String, contains query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: options, locale: nil)
        return normalizedQuery.isEmpty || text.folding(options: options, locale: nil).contains(normalizedQuery)
    }
}
