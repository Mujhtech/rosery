import Foundation

nonisolated struct QuranChapter: Decodable, Identifiable, Sendable {
    let id: Int
    let nameSimple: String
    let nameArabic: String
    let versesCount: Int
    let revelationPlace: String

    enum CodingKeys: String, CodingKey {
        case id
        case nameSimple = "name_simple"
        case nameArabic = "name_arabic"
        case versesCount = "verses_count"
        case revelationPlace = "revelation_place"
    }
}

nonisolated struct QuranVerse: Decodable, Identifiable, Sendable {
    let id: Int
    let verseNumber: Int
    let verseKey: String
    let textUthmani: String?

    enum CodingKeys: String, CodingKey {
        case id
        case verseNumber = "verse_number"
        case verseKey = "verse_key"
        case textUthmani = "text_uthmani"
    }
}

nonisolated struct QuranVersePage: Decodable, Sendable {
    let verses: [QuranVerse]
    let pagination: Pagination

    struct Pagination: Decodable, Sendable {
        let currentPage: Int
        let nextPage: Int?
        let totalPages: Int

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case nextPage = "next_page"
            case totalPages = "total_pages"
        }
    }
}
