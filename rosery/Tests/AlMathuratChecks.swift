import Foundation

/// Protects the imported edition's order, provenance, editorial boundaries, and reader behavior.
@main
struct AlMathuratChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let source = root.appendingPathComponent("ContentSources/al-mathurat/al-mathurat.json")
        let resource = root.appendingPathComponent("rosery/Content/al-mathurat.json")
        let sourceData = try Data(contentsOf: source)
        let resourceData = try Data(contentsOf: resource)
        precondition(sourceData == resourceData, "The app must bundle the reviewed edition verbatim")
        let booklet = try AlMathuratBooklet.load(from: resource)
        let entries = booklet.entries
        precondition(booklet.document.pdfPageCount == 22)
        precondition(entries.map(\.sourceItemNumber) == Array(1...28))
        precondition(entries.map(\.id) == (1...28).map { String(format: "al-mathurat-%02d", $0) })

        for entry in entries {
            let expectedCount = (6...24).contains(entry.sourceItemNumber) ? 3 : nil
            precondition(entry.repetitions == expectedCount, "Unspecified booklet counts must remain unspecified")
            precondition(entry.repetitionLabel == (expectedCount == nil ? "Count not specified" : "3 times in booklet"))
            precondition(!entry.arabicSource.isEmpty && !entry.arabicNormalized.isEmpty)
            for text in [entry.arabicSource, entry.arabicNormalized] {
                precondition(!text.unicodeScalars.contains { scalar in
                    let value = scalar.value
                    return (0xE000...0xF8FF).contains(value) ||
                        (0xF0000...0xFFFFD).contains(value) || (0x100000...0x10FFFD).contains(value)
                }, "The booklet's private-use font encoding must not reach the reader")
            }
            let pages = entry.pageReferences.arabic + entry.pageReferences.transliteration + entry.pageReferences.translation
            precondition(!pages.isEmpty && pages.allSatisfy { (1...22).contains($0) })
            precondition(Set(pages).isSubset(of: Set(entry.sourcePages)))
            precondition(entry.transliteration == removingPrintedCount(entry.transliterationSource))
            precondition(entry.translation == removingPrintedCount(entry.translationSource))
        }

        let normalizedNumbers = [11, 20, 23, 24, 27]
        precondition(entries.filter(\.normalizationApplied).map(\.sourceItemNumber) == normalizedNumbers)
        precondition(entries.filter { $0.arabicSource != $0.arabicNormalized }.map(\.sourceItemNumber) == normalizedNumbers)
        precondition(entries[9].arabicNormalized == entries[9].arabicSource)
        precondition(!entries[9].arabicNormalized.contains("مسلما"), "Do not silently replace the booklet's narration variant")

        let aligned = entries[26]
        precondition(entries.filter { $0.translationAligned != nil }.map(\.sourceItemNumber) == [27])
        precondition(aligned.translation.hasPrefix("Oh Allah! this is the coming of Your night"))
        precondition(aligned.translation.hasSuffix("Oh Allah. Ameen."))
        precondition(aligned.meaning.hasPrefix("Oh Allah, You know that these hearts"))
        precondition(aligned.meaning.hasSuffix("the best to give victory."))
        precondition(!aligned.meaning.contains("coming of Your night"))
        precondition(aligned.meaningNote != nil && aligned.translationAlignmentNote != nil)
        precondition(entries.filter { $0.sourceItemNumber != 27 }.allSatisfy { $0.meaning == $0.translation })

        precondition(booklet.readings(matching: "  AL-MATHURAT  ").count == 28)
        precondition(booklet.readings(matching: "").count == 28)
        precondition(booklet.readings(matching: "never a booklet phrase 4321").isEmpty)
        precondition(booklet.matches("المأثورات"))
        precondition(aligned.matches("these hearts"))
        precondition(!aligned.matches("coming of Your night"), "Search must follow the meaning actually displayed")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-booklet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporaryURL = directory.appendingPathComponent("edition.json")
        let original = try JSONSerialization.jsonObject(with: sourceData) as! [String: Any]
        try expectInvalid(original, at: temporaryURL) { $0["schemaVersion"] = 2 }
        try expectInvalid(original, at: temporaryURL) { json in
            var readings = json["entries"] as! [[String: Any]]
            readings.swapAt(0, 1)
            json["entries"] = readings
        }
        try expectInvalid(original, at: temporaryURL) { json in
            var readings = json["entries"] as! [[String: Any]]
            readings[1]["id"] = readings[0]["id"]
            json["entries"] = readings
        }
        try expectInvalid(original, at: temporaryURL) { json in
            var readings = json["entries"] as! [[String: Any]]
            readings[0]["sourcePages"] = [23]
            json["entries"] = readings
        }
        do {
            _ = try AlMathuratBooklet.load(from: nil)
            preconditionFailure("A missing resource must fail explicitly")
        } catch AlMathuratBooklet.LoadingError.missingResource { }
        print("PASS: 28 ordered booklet readings; 19 printed counts and 9 unspecified; Unicode Arabic; documented normalization only; translation alignment with raw source retained; identical bundled edition; reader search; malformed edition rejection.")
    }

    private static func expectInvalid(_ original: [String: Any], at url: URL, mutate: (inout [String: Any]) -> Void) throws {
        var changed = original
        mutate(&changed)
        try JSONSerialization.data(withJSONObject: changed).write(to: url)
        do {
            _ = try AlMathuratBooklet.load(from: url)
            preconditionFailure("Invalid edition was accepted")
        } catch AlMathuratBooklet.LoadingError.invalidEdition { }
    }

    private static func removingPrintedCount(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+\(3 times\)$"#, with: "", options: [.caseInsensitive, .regularExpression])
    }
}
