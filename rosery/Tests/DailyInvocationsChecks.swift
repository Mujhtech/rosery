import Foundation

/// Checks the photographed edition's provenance and the reader's search/navigation contract.
@main
struct DailyInvocationsChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let source = root.appendingPathComponent("ContentSources/daily-invocations/daily-invocations.json")
        let resource = root.appendingPathComponent("rosery/Content/daily-invocations.json")
        let sourceData = try Data(contentsOf: source)
        let resourceData = try Data(contentsOf: resource)
        precondition(sourceData == resourceData, "The app must bundle the source edition verbatim")
        let booklet = try DailyInvocationsBooklet.load(from: resource)
        precondition(booklet.document.firstPage == 81 && booklet.document.lastPage == 152)
        precondition(booklet.document.photoCount == 36)
        precondition(!booklet.document.notes.isEmpty, "The photographed excerpt needs its edition notes")
        precondition(booklet.entries.count == 96)
        precondition(booklet.sections(matching: "").count == 20)
        precondition(booklet.entries.filter { $0.arabic != nil }.count == 88)
        precondition(booklet.entries.filter { $0.arabic == nil && $0.transliteration != nil }.map(\.id) == [
            "daily-after-prayer-subhanallah", "daily-after-prayer-alhamdulillah", "daily-after-prayer-allahu-akbar"
        ], "The three Latin-only source phrases must not acquire invented Arabic")
        precondition(booklet.entries.filter { $0.arabic == nil && $0.transliteration == nil }.map(\.id) == [
            "daily-dream-guidance", "daily-bedtime-three-surahs", "daily-new-baby-guidance",
            "daily-conveyed-greeting", "daily-condolence-letter-guidance"
        ], "Practice guidance must not acquire Arabic absent from the photographed source")
        let printedCounts = Dictionary(uniqueKeysWithValues: booklet.entries.compactMap { entry in
            entry.repetitions.map { (entry.id, $0) }
        })
        precondition(printedCounts == [
            "daily-bedtime-forgiveness": 3,
            "daily-after-prayer-subhanallah": 33,
            "daily-after-prayer-alhamdulillah": 33,
            "daily-after-prayer-allahu-akbar": 33,
            "daily-after-prayer-hundredth": 1,
            "daily-new-month-goodness": 3,
            "daily-pain-bismillah": 3,
            "daily-pain-seeking-refuge": 7
        ], "Only explicit recitation counts belong in the count field")
        let variedCounts = Dictionary(uniqueKeysWithValues: booklet.entries.compactMap { entry in
            entry.repetitionGuidance.map { (entry.id, $0) }
        })
        precondition(variedCounts == ["daily-rainfall": "2 or 3 times in source",
                                     "daily-salatut-tasbih": "Counts vary by prayer stage"],
                     "Variable and stage counts must stay separate from fixed recitation counts")
        precondition(booklet.entries.prefix(45).allSatisfy { $0.sourcePart == "Daily routines · pages 81–114" })
        precondition(booklet.entries.dropFirst(45).allSatisfy { $0.sourcePart == "Section Four · Various situations" })
        precondition(booklet.entries[0].sourceFootnotes.contains(1) && booklet.entries[45].sourceFootnotes.contains(1),
                     "Footnote numbering restarts in Section Four and needs its source-part context")
        let criticalNotes = ["daily-sleep-and-wakefulness", "daily-walking-to-mosque", "daily-after-adhan",
                             "daily-meal-host", "daily-night-prayer", "daily-quiet-night", "daily-lying-down",
                             "daily-surrender-before-sleep", "daily-gathering-forgiveness", "daily-prayer-of-need",
                             "daily-child-protection", "daily-first-fruit", "daily-quran-comfort-in-distress",
                             "daily-salatut-tasbih"]
        for id in criticalNotes {
            precondition(booklet.entries.first { $0.id == id }?.readingNote != nil,
                         "Source layer differences must be visible before reciting")
        }
        let mosque = try arabic(for: "daily-walking-to-mosque", in: booklet)
        precondition(!mosque.contains("يسار") && !mosque.contains("فوق") && !mosque.contains("تحت"),
                     "Do not silently fill the mosque invocation's missing clauses")
        let adhan = try arabic(for: "daily-after-adhan", in: booklet)
        precondition(!adhan.contains("محمود"),
                     "Do not silently fill the adhan invocation's omitted word")
        let bedtime = try arabic(for: "daily-surrender-before-sleep", in: booklet)
        precondition(!bedtime.contains("منجا"),
                     "Do not silently fill the bedtime invocation's omitted word")
        let distress = try arabic(for: "daily-quran-comfort-in-distress", in: booklet)
        precondition(distress.contains("نور بصري") && !distress.contains("نور صدري"),
                     "Preserve the photographed Arabic beside its documented English difference")
        precondition(booklet.entries.map(\.order) == Array(1...booklet.entries.count))
        precondition(booklet.sections(matching: "").flatMap(\.entries).map(\.id) == booklet.entries.map(\.id))
        precondition(booklet.readings(matching: "  DAILY INVOCATIONS  ").count == booklet.entries.count)
        precondition(booklet.readings(matching: "never a source phrase 83516").isEmpty)

        let raw = try JSONSerialization.jsonObject(with: sourceData) as! [String: Any]
        let rawEntries = raw["entries"] as! [[String: Any]]
        for (entry, printed) in zip(booklet.entries, rawEntries) {
            precondition(entry.arabic == printed["arabic"] as? String, "Do not silently replace source Arabic")
            precondition(entry.repetitions == printed["repetitions"] as? Int, "Unspecified counts stay unspecified")
            precondition(entry.translation == printed["translation"] as? String)
            precondition(entry.transliteration == printed["transliteration"] as? String)
            precondition(entry.readingNote == printed["readingNote"] as? String)
            precondition(entry.notes == printed["notes"] as? [String])
            precondition(entry.sourcePart == printed["sourcePart"] as? String)
            precondition(entry.sourceFootnotes == printed["sourceFootnotes"] as? [Int])
            precondition(entry.repetitionGuidance == printed["repetitionGuidance"] as? String)
            if entry.repetitions == nil {
                let expectedLabel = entry.repetitionGuidance ??
                    (entry.arabic == nil && entry.transliteration == nil ? "Reading guidance" : "Count not specified")
                precondition(entry.repetitionLabel == expectedLabel)
            }
            precondition(booklet.readings(matching: entry.title).contains { $0.id == entry.id })
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-daily-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("edition.json")
        let fixture = fixtureJSON()
        try write(fixture, to: temporary)
        let searchable = try DailyInvocationsBooklet.load(from: temporary)
        precondition(searchable.readings(matching: "الحمد لله").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "  WAKE UP ").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "Alhamdu").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "All praise").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "heading about waking").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "before breakfast").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "visible variant").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "layer difference").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "Source group alpha").map(\.id) == ["daily-test-1"])
        precondition(searchable.readings(matching: "Morning").map(\.id) == ["daily-test-1", "daily-test-2"])
        precondition(searchable.readings(matching: "Companion on the Path").count == 3)
        precondition(searchable.sections(matching: "").map(\.title) == ["Morning", "Evening"])
        precondition(searchable.entries[1].translation == nil && searchable.entries[1].transliteration == nil)
        precondition(searchable.entries[2].arabic == nil && !searchable.entries[2].practice.isEmpty,
                     "Guidance without printed Arabic must remain guidance")
        precondition(searchable.entries[2].repetitionLabel == "Reading guidance")
        precondition(searchable.entries[1].repetitions == nil && searchable.entries[1].repetitionLabel == "2 or 3 times in source",
                     "A variable source count must not become an arbitrary fixed count")
        precondition(searchable.entries[0].footnoteLabel == "Printed footnote 12")
        precondition(searchable.entries[1].footnoteLabel == nil)

        try expectInvalid(fixture, at: temporary) { $0["schemaVersion"] = 2 }
        try expectInvalid(fixture, at: temporary) { $0["entries"] = [] }
        try expectInvalid(fixture, at: temporary) { json in
            var document = json["document"] as! [String: Any]
            document["firstPage"] = 153
            json["document"] = document
        }
        try expectInvalid(fixture, at: temporary) { json in
            var entries = json["entries"] as! [[String: Any]]
            entries.swapAt(0, 1)
            json["entries"] = entries
        }
        try expectInvalidEntry(fixture, at: temporary, key: "id", value: "daily-test-2")
        try expectInvalidEntry(fixture, at: temporary, key: "arabic", value: " \n ")
        try expectInvalidEntry(fixture, at: temporary, key: "arabic", value: "\u{E001}")
        try expectInvalidEntry(fixture, at: temporary, key: "repetitions", value: 0)
        try expectInvalidEntry(fixture, at: temporary, key: "sourcePages", value: [153])
        try expectInvalidEntry(fixture, at: temporary, key: "sourcePages", value: [81, 81])
        try expectInvalidEntry(fixture, at: temporary, key: "sourcePages", value: [])
        try expectInvalidEntry(fixture, at: temporary, key: "sourceFootnotes", value: [-1])
        try expectInvalidEntry(fixture, at: temporary, key: "sourceFootnotes", value: [12, 12])
        try expectInvalidEntry(fixture, at: temporary, key: "translation", value: "")
        try expectInvalidEntry(fixture, at: temporary, key: "readingNote", value: " ")
        try expectInvalidEntry(fixture, at: temporary, key: "sourcePart", value: " ")
        try expectInvalidEntry(fixture, at: temporary, key: "repetitionGuidance", value: " ")
        try expectInvalidEntry(fixture, at: temporary, key: "repetitionGuidance", value: "Counts vary by stage")
        try expectInvalid(fixture, at: temporary) { json in
            var entries = json["entries"] as! [[String: Any]]
            entries[2]["practice"] = ""
            json["entries"] = entries
        }
        do {
            _ = try DailyInvocationsBooklet.load(from: nil)
            preconditionFailure("A missing resource must fail explicitly")
        } catch DailyInvocationsBooklet.LoadingError.missingResource { }
        print("PASS: \(booklet.entries.count) ordered daily invocations; exact bundled source; printed page and footnote references; unspecified counts retained; optional source text; Arabic and English search; grouped contents; malformed edition rejection.")
    }

    private static func fixtureJSON() -> [String: Any] {
        [
            "schemaVersion": 1,
            "document": ["title": "Daily invocations", "sourceTitle": "Companion on the Path",
                         "subtitle": "A photographed excerpt", "firstPage": 81, "lastPage": 152,
                         "photoCount": 36, "notes": ["Printed edition notes."]],
            "entries": [
                ["id": "daily-test-1", "order": 1, "section": "Morning", "sourceHeading": "Heading about waking",
                 "title": "Wake up", "arabic": "ٱلْحَمْـدُ لِلَّهِ", "transliteration": "Alhamdu lillah",
                 "translation": "All praise belongs to Allah.", "practice": "Read before breakfast.",
                 "repetitions": 3, "sourcePages": [81], "sourceFootnotes": [12],
                 "sourcePart": "Source group alpha",
                 "readingNote": "A source layer difference.", "notes": ["A visible variant."]],
                ["id": "daily-test-2", "order": 2, "section": "Morning", "sourceHeading": "Second heading",
                 "title": "Second invocation", "arabic": "بسم الله", "practice": "", "repetitions": NSNull(),
                 "repetitionGuidance": "2 or 3 times in source",
                 "sourcePages": [82], "sourceFootnotes": [], "notes": []],
                ["id": "daily-test-3", "order": 3, "section": "Evening", "sourceHeading": "Third heading",
                 "title": "Third invocation", "arabic": NSNull(), "practice": "Act on this guidance.", "repetitions": NSNull(),
                 "sourcePages": [83], "sourceFootnotes": [13, 14], "notes": []]
            ]
        ]
    }

    private static func arabic(for id: String, in booklet: DailyInvocationsBooklet) throws -> String {
        guard let text = booklet.entries.first(where: { $0.id == id })?.arabic else {
            throw CheckError.missingReading
        }
        let scalars = text.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }
        return String(String.UnicodeScalarView(scalars)).folding(options: [.diacriticInsensitive], locale: nil)
    }

    private enum CheckError: Error { case missingReading }

    private static func write(_ json: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    private static func expectInvalidEntry(_ original: [String: Any], at url: URL, key: String, value: Any) throws {
        try expectInvalid(original, at: url) { json in
            var entries = json["entries"] as! [[String: Any]]
            entries[0][key] = value
            json["entries"] = entries
        }
    }

    private static func expectInvalid(_ original: [String: Any], at url: URL,
                                      mutate: (inout [String: Any]) -> Void) throws {
        var changed = original
        mutate(&changed)
        try write(changed, to: url)
        do {
            _ = try DailyInvocationsBooklet.load(from: url)
            preconditionFailure("Invalid edition was accepted")
        } catch DailyInvocationsBooklet.LoadingError.invalidEdition { }
    }
}
