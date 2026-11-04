import Foundation

/// An isolated defaults store exercises the real JSON encoding/decoding without touching user data.
nonisolated final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

/// Fails after the domain operation, exercising a rejected persistence commit.
nonisolated final class FailableStorage: TasbihStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var rejectWrites = false

    func failWrites() {
        lock.lock()
        defer { lock.unlock() }
        rejectWrites = true
    }

    func withData<Result>(_ operation: (inout Data?) throws -> Result) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        var next = data
        let result = try operation(&next)
        if rejectWrites, next != data { throw Failure.writeRejected }
        data = next
        return result
    }

    private enum Failure: Error { case writeRejected }
}

@main
struct CoreChecks {
    @MainActor
    static func main() throws {
        if CommandLine.arguments.dropFirst().first == "--widget-worker" {
            try runWidgetWorker()
            return
        }
        let defaults = MemoryDefaults()
        let store = RoseryStore(defaults: defaults)
        let praise = try require(DhikrLibrary.reading(id: "alhamdulillah"))
        let ikhlas = try require(DhikrLibrary.reading(id: "al-ikhlas"))
        let healing = try require(DhikrLibrary.reading(id: "healing"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        assert(store.progress.count == 0 && store.progress.target == 33)
        for _ in 0..<33 { store.increment(now: date) }
        assert(store.progress.isComplete && store.sessions.count == 1)
        assert(store.sessions[0].date == date && store.sessions[0].count == 33)
        store.increment()
        assert(store.progress.count == 33 && store.sessions.count == 1, "Completion must not duplicate")
        store.undo()
        assert(store.progress.count == 32 && store.sessions.isEmpty, "Undo reverses the completed round")
        store.increment()
        assert(store.sessions.count == 1)
        assert(store.nextAfterPrayer?.id == "alhamdulillah")
        store.beginNextAfterPrayer()
        assert(store.selectedDhikr.id == praise.id && store.progress.count == 0)
        store.increment()
        store.increment()
        store.select(DhikrLibrary.primary)
        assert(store.progress.isComplete, "Each dhikr keeps its own count")
        store.select(praise)
        assert(store.progress.count == 2)

        store.resetCounter(target: 1)
        store.increment()
        assert(store.isPersonalTarget && store.nextAfterPrayer == nil)
        assert(store.sessions.count == 2)
        store.resetCounter()
        assert(store.sessions.count == 2, "Restart retains previous completed rounds")
        store.undo()
        assert(store.progress.count == 0, "Undo cannot go below zero")

        store.resetCounter(target: -4)
        assert(store.progress.target == 1)
        store.resetCounter(target: 99_999)
        assert(store.progress.target == 10_000)
        store.resetCounter(target: 33)
        store.increment()

        store.toggleBookmark(ikhlas)
        assert(store.isBookmarked(ikhlas))
        store.toggleBookmark(ikhlas)
        assert(!store.isBookmarked(ikhlas))
        store.toggleBookmark(ikhlas)
        for _ in 0..<5 { store.markRecitation(for: ikhlas) }
        assert(store.readingCount(for: ikhlas) == 3)
        store.markRecitation(for: healing)
        store.markRecitation(for: healing)
        assert(store.readingCount(for: healing) == 1)
        store.resetReading(healing)
        assert(store.readingCount(for: healing) == 0)
        store.updatePreferences { $0.haptics = false; $0.appearance = .light; $0.largeArabic = true }

        let restored = RoseryStore(defaults: defaults)
        assert(restored.selectedDhikr.id == praise.id && restored.progress.count == 1)
        assert(restored.bookmarks.map(\.id) == [ikhlas.id])
        assert(restored.sessions.count == 2)
        assert(restored.readingCount(for: ikhlas) == 3)
        assert(!restored.preferences.haptics && restored.preferences.largeArabic)
        assert(restored.preferences.appearance == .light)

        assert(DhikrLibrary.primary.matches("  SUBHANALLAH  "))
        assert(praise.matches("الحمد"), "Arabic search ignores diacritics")
        assert(ikhlas.matches("ikhlas"))
        assert(healing.matches("5743"), "References are searchable")
        assert(!healing.matches("nonexistent query"))
        assert(DhikrCollection.allCases.allSatisfy { !$0.readings.isEmpty })
        assert(Set(DhikrLibrary.readings.map(\.id)).count == DhikrLibrary.readings.count)
        assert(DhikrLibrary.readings.count == 19)
        assert(DhikrLibrary.readings.allSatisfy { !$0.arabic.isEmpty && !$0.sources.isEmpty })
        assert(DhikrLibrary.readings.flatMap(\.sources).allSatisfy { $0.url?.scheme == "https" })

        defaults.set(Data("invalid saved state".utf8), forKey: "rosery.saved-state.v1")
        let recovered = RoseryStore(defaults: defaults)
        assert(recovered.progress.count == 0 && recovered.progress.target == 33)
        try checkSharedPersistence()
        try checkTargetChanges()
        try checkBeadAppearance()
        print("PASS: original core behavior; build 1 migration; widget-before-launch; stale-widget rejection; app/widget transaction merging; cross-process counts; exactly-once completion; count-preserving targets and history reconciliation; per-dhikr target persistence; stale-editor protection; bead appearance migration, round trips and atomic persistence; rejected storage commits; corrupt-file preservation.")
    }

    @MainActor
    private static func checkBeadAppearance() throws {
        assert(BeadAppearance.standard == BeadAppearance(material: .polished, color: .onyx, shape: .oval))
        assert(TasbihSnapshot.needsApp.beadAppearance == .standard)
        assert(TasbihSnapshot.preview.beadAppearance == .standard)
        for material in BeadAppearance.Material.allCases {
            for color in BeadAppearance.Color.allCases {
                for shape in BeadAppearance.Shape.allCases {
                    let appearance = BeadAppearance(material: material, color: color, shape: shape)
                    let encoded = try JSONEncoder().encode(appearance)
                    let decoded = try JSONDecoder().decode(BeadAppearance.self, from: encoded)
                    assert(decoded == appearance)
                }
            }
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-beads-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("state-v2.json")
        let repository = TasbihRepository(storage: TasbihFileStorage(directory: directory))
        let widget = TasbihRepository(storage: TasbihFileStorage(directory: directory))

        // Existing schema 2 files predate the appearance key and must preserve every other value.
        let session = DhikrSession(id: UUID(), dhikrID: "alhamdulillah", count: 1,
                                   date: Date(timeIntervalSince1970: 1_700_000_000))
        var seed = TasbihState()
        seed.bookmarks = ["al-ikhlas", "healing"]
        seed.counters = [seed.selectedID: CounterProgress(count: 17, target: 100),
                         "alhamdulillah": CounterProgress(count: 1, target: 1, completedSessionID: session.id)]
        seed.readingCounts = ["al-ikhlas": 2]
        seed.sessions = [session]
        seed.preferences = ReadingPreferences(haptics: false, transliteration: false, largeArabic: true, appearance: .dark)
        var oldJSON = try require(JSONSerialization.jsonObject(with: JSONEncoder().encode(seed)) as? [String: Any])
        oldJSON["schemaVersion"] = 2
        oldJSON.removeValue(forKey: "beadAppearance")
        let oldData = try JSONSerialization.data(withJSONObject: oldJSON)
        let decodedOld = try JSONDecoder().decode(TasbihState.self, from: oldData)
        assert(decodedOld == seed, "Missing appearance must not reset existing schema 2 state")
        oldJSON["beadAppearance"] = NSNull()
        let nullData = try JSONSerialization.data(withJSONObject: oldJSON)
        let decodedNull = try JSONDecoder().decode(TasbihState.self, from: nullData)
        assert(decodedNull == seed)
        try oldData.write(to: stateURL, options: .atomic)
        let app = try RoseryStore(repository: repository)
        let staleEditor = try RoseryStore(repository: repository)
        let migrated = try require(repository.readState())
        assert(migrated == seed && app.beadAppearance == .standard)

        // A style save must merge a widget's newer count and retain its valid round token.
        let beforeWidget = try widget.snapshot()
        _ = try widget.increment(expectedDhikrID: beforeWidget.selectedID, expectedGeneration: beforeWidget.generation)
        var expected = try require(widget.readState())
        let chosen = BeadAppearance(material: .wood, color: .amber, shape: .faceted)
        var notifications = 0
        app.onCounterChange = { notifications += 1 }
        assert(app.updateBeadAppearance { $0 = chosen })
        expected.beadAppearance = chosen
        expected.syncRevision += 1
        let saved = try require(repository.readState())
        assert(saved == expected, "Appearance and its sync revision are the only fields changed by the save")
        assert(app.progress.count == 18 && app.progress.generation.uuidString == beforeWidget.generation)
        let styledSnapshot = try widget.snapshot()
        assert(styledSnapshot.beadAppearance == chosen && notifications == 1)
        let savedBytes = try Data(contentsOf: stateURL)
        assert(app.updateBeadAppearance { $0 = chosen })
        let sameBytes = try Data(contentsOf: stateURL)
        assert(savedBytes == sameBytes && notifications == 1, "Saving the same style does not refresh the widget")

        // Property edits from another app adapter operate on the latest appearance, not its stale copy.
        assert(staleEditor.updateBeadAppearance { $0.color = .ocean })
        expected.beadAppearance.color = .ocean
        expected.syncRevision += 1
        let afterSecondEditor = try require(repository.readState())
        assert(afterSecondEditor == expected)
        let afterTap = try widget.increment(expectedDhikrID: beforeWidget.selectedID, expectedGeneration: beforeWidget.generation)
        expected.counters[expected.selectedID]?.count += 1
        expected.syncRevision += 1
        assert(afterTap.count == 19 && afterTap.beadAppearance == expected.beadAppearance)
        let relaunched = try RoseryStore(repository: repository)
        assert(relaunched.beadAppearance == expected.beadAppearance)
        let restored = try require(repository.readState())
        assert(restored == expected, "Relaunch preserves style, counters, history, bookmarks and reading preferences")
        app.refreshFromShared()
        assert(app.beadAppearance == expected.beadAppearance && app.progress.count == 19)

        let failable = FailableStorage()
        let failedRepository = TasbihRepository(storage: failable)
        let failedApp = try RoseryStore(repository: failedRepository)
        var failedNotifications = 0
        failedApp.onCounterChange = { failedNotifications += 1 }
        failable.failWrites()
        assert(!failedApp.updateBeadAppearance { $0 = chosen })
        assert(failedApp.beadAppearance == .standard && failedApp.persistenceError != nil && failedNotifications == 0)
        let unchanged = try require(failedRepository.readState())
        assert(unchanged.beadAppearance == .standard)
    }

    @MainActor
    private static func checkTargetChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-targets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TasbihRepository(storage: TasbihFileStorage(directory: directory))
        let widget = TasbihRepository(storage: TasbihFileStorage(directory: directory))
        let app = try RoseryStore(repository: repository)
        let praise = try require(DhikrLibrary.reading(id: "alhamdulillah"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        // Keep an older completed round while extending the current completed round.
        app.resetCounter(target: 1)
        app.increment(now: date)
        let historicalID = try require(app.sessions.first?.id)
        app.resetCounter(target: 33)
        for _ in 0..<33 { app.increment(now: date.addingTimeInterval(100)) }
        assert(app.sessions.count == 2 && app.progress.isComplete)
        let completedID = try require(app.progress.completedSessionID)
        let oldWidget = try widget.snapshot()
        let editorID = app.selectedDhikr.id
        let editorGeneration = app.progress.generation
        var notifications = 0
        app.onCounterChange = { notifications += 1 }
        assert(app.setTarget(100, expectedID: editorID, expectedGeneration: editorGeneration))
        assert(app.progress.count == 33 && app.progress.target == 100 && !app.progress.isComplete)
        assert(app.progress.completedSessionID == nil && app.nextAfterPrayer == nil)
        assert(app.progress.generation != editorGeneration && notifications == 1)
        assert(app.sessions.map(\.id) == [historicalID] && !app.sessions.contains { $0.id == completedID })
        let rejectedOldTap = try widget.increment(expectedDhikrID: oldWidget.selectedID, expectedGeneration: oldWidget.generation)
        assert(rejectedOldTap.count == 33, "A widget drawn before retargeting must not count into the extended round")

        let unchangedGeneration = app.progress.generation
        assert(app.setTarget(100))
        assert(app.progress.generation == unchangedGeneration && notifications == 1, "Saving the same target is a no-op")
        let freshWidget = try widget.snapshot()
        _ = try widget.increment(expectedDhikrID: freshWidget.selectedID, expectedGeneration: freshWidget.generation)
        app.refreshFromShared()
        assert(app.progress.count == 34)

        let beforeRejected = try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))
        assert(!app.setTarget(33), "A smaller target cannot silently truncate a count")
        let afterRejected = try Data(contentsOf: directory.appendingPathComponent("state-v2.json"))
        assert(beforeRejected == afterRejected && app.progress.count == 34 && app.progress.target == 100)
        let completedAt = date.addingTimeInterval(200)
        assert(app.setTarget(34, now: completedAt))
        assert(app.progress.count == 34 && app.progress.isComplete && app.sessions.count == 2)
        assert(app.sessions[0].id == app.progress.completedSessionID)
        assert(app.sessions[0].count == 34 && app.sessions[0].date == completedAt)
        let equalitySession = app.sessions[0]
        assert(app.setTarget(34, now: date.addingTimeInterval(300)))
        assert(app.sessions[0] == equalitySession && app.sessions.count == 2, "Equality creates only one completion")
        assert(!app.setTarget(20))
        assert(app.sessions[0] == equalitySession && app.progress.count == 34 && app.progress.target == 34)

        assert(app.setTarget(100))
        for _ in 34..<100 { app.increment(now: date.addingTimeInterval(400)) }
        assert(app.sessions.count == 2 && app.sessions[0].count == 100)
        assert(app.sessions[1].id == historicalID, "Retargeting must never erase earlier rounds")
        assert(!app.sessions.contains { $0.id == equalitySession.id || $0.id == completedID })
        app.undo()
        assert(app.progress.count == 99 && !app.progress.isComplete && app.sessions.map(\.id) == [historicalID])
        assert(app.setTarget(99))
        assert(app.progress.isComplete && app.sessions[0].count == 99 && app.sessions.count == 2)
        assert(app.setTarget(100))
        assert(app.sessions.map(\.id) == [historicalID])

        // Each phrase retains its custom target through selection changes and a new app adapter.
        app.select(praise)
        assert(app.setTarget(500))
        for _ in 0..<7 { app.increment() }
        app.select(DhikrLibrary.primary)
        assert(app.progress.count == 99 && app.progress.target == 100)
        let relaunched = try RoseryStore(repository: repository)
        assert(relaunched.progress.count == 99 && relaunched.progress.target == 100)
        relaunched.select(praise)
        assert(relaunched.progress.count == 7 && relaunched.progress.target == 500)
        relaunched.select(DhikrLibrary.primary)
        app.refreshFromShared()

        let staleID = app.selectedDhikr.id
        let staleGeneration = app.progress.generation
        app.select(praise)
        assert(!app.setTarget(200, expectedID: staleID, expectedGeneration: staleGeneration))
        assert(!app.resetCounter(target: 33, expectedID: staleID, expectedGeneration: staleGeneration))
        assert(app.selectedDhikr.id == praise.id && app.progress.count == 7 && app.progress.target == 500)
        app.select(DhikrLibrary.primary)
        assert(!app.setTarget(200, expectedID: staleID, expectedGeneration: staleGeneration))
        assert(!app.resetCounter(target: 33, expectedID: staleID, expectedGeneration: staleGeneration))
        assert(app.progress.count == 99 && app.progress.target == 100, "Returning to the phrase does not revive an old editor")

        let beforeResetGeneration = app.progress.generation
        app.resetCounter(target: 100)
        app.increment()
        assert(!app.setTarget(200, expectedID: staleID, expectedGeneration: beforeResetGeneration))
        assert(!app.resetCounter(target: 33, expectedID: staleID, expectedGeneration: beforeResetGeneration))
        assert(app.progress.count == 1 && app.progress.target == 100, "A pending reset confirmation cannot clear a newer round")

        let beforeOtherEdit = app.progress.generation
        let otherEditor = try RoseryStore(repository: repository)
        assert(otherEditor.setTarget(200))
        assert(!app.setTarget(300, expectedID: staleID, expectedGeneration: beforeOtherEdit))
        assert(app.progress.target == 200 && app.progress.count == 1, "A rejected editor refreshes to the newer saved target")

        // A widget may count while the picker is open. Revalidate count inside the transaction.
        app.resetCounter(target: 100)
        for _ in 0..<10 { app.increment() }
        let racingID = app.selectedDhikr.id
        let racingGeneration = app.progress.generation
        let racingWidget = try widget.snapshot()
        for _ in 0..<2 {
            _ = try widget.increment(expectedDhikrID: racingWidget.selectedID, expectedGeneration: racingWidget.generation)
        }
        assert(!app.setTarget(11, expectedID: racingID, expectedGeneration: racingGeneration))
        assert(app.progress.count == 12 && app.progress.target == 100 && app.progress.generation == racingGeneration)
        assert(app.setTarget(12, expectedID: racingID, expectedGeneration: racingGeneration))
        assert(app.progress.isComplete && app.sessions[0].count == 12 && app.sessions.count == 2)

        let resetID = app.selectedDhikr.id
        let resetGeneration = app.progress.generation
        assert(app.resetCounter(target: 5, expectedID: resetID, expectedGeneration: resetGeneration))
        assert(app.progress.count == 0 && app.progress.target == 5 && app.sessions.count == 2)
        assert(app.setTarget(-4) && app.progress.target == 1)
        assert(app.setTarget(99_999) && app.progress.target == 10_000)
        let finalState = try require(repository.readState())
        assert(finalState.counters.values.allSatisfy { (1...10_000).contains($0.target) && (0...$0.target).contains($0.count) })

        let failable = FailableStorage()
        let failedRepository = TasbihRepository(storage: failable)
        let failedApp = try RoseryStore(repository: failedRepository)
        var failedNotifications = 0
        failedApp.onCounterChange = { failedNotifications += 1 }
        failable.failWrites()
        assert(!failedApp.setTarget(100))
        assert(!failedApp.resetCounter(target: 500))
        assert(failedApp.progress.target == 33 && failedApp.persistenceError != nil && failedNotifications == 0)
        let unchangedState = try require(failedRepository.readState())
        assert(unchangedState.progress.target == 33, "A failed commit must never report an accepted target change")
    }

    @MainActor
    private static func checkSharedPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-core-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appRepository = TasbihRepository(storage: TasbihFileStorage(directory: directory))
        let widget = TasbihRepository(storage: TasbihFileStorage(directory: directory))

        // A widget added immediately after an upgrade cannot preempt migration from build 1.
        let uninitialized = try widget.snapshot()
        assert(uninitialized.needsOpenApp)
        let premature = try widget.increment(expectedDhikrID: uninitialized.selectedID, expectedGeneration: uninitialized.generation)
        assert(premature.needsOpenApp)
        let untouched = try appRepository.readState()
        assert(untouched == nil)

        let sessionID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        // This is the exact old JSON shape: no schema version or generation fields.
        let legacy = try JSONSerialization.data(withJSONObject: [
            "selectedID": "subhanallah",
            "bookmarks": ["al-ikhlas"],
            "counters": [
                "subhanallah": ["count": 17, "target": 33],
                "alhamdulillah": ["count": 1, "target": 1, "completedSessionID": sessionID.uuidString]
            ],
            "readingCounts": ["al-ikhlas": 2],
            "sessions": [["id": sessionID.uuidString, "dhikrID": "alhamdulillah", "count": 1,
                          "date": date.timeIntervalSinceReferenceDate]],
            "preferences": ["haptics": false, "transliteration": false, "largeArabic": true, "appearance": "dark"]
        ])
        let app = try RoseryStore(repository: appRepository, legacyData: legacy)
        let migrated = try require(appRepository.readState())
        assert(app.progress.count == 17 && app.progress.target == 33)
        assert(app.bookmarks.map(\.id) == ["al-ikhlas"])
        assert(migrated.readingCounts["al-ikhlas"] == 2)
        assert(app.sessions.count == 1 && app.sessions[0].id == sessionID && app.sessions[0].date == date)
        assert(migrated.counters["alhamdulillah"]?.completedSessionID == sessionID)
        assert(!app.preferences.haptics && !app.preferences.transliteration && app.preferences.largeArabic)
        assert(app.preferences.appearance == .dark)
        assert(app.beadAppearance == .standard && migrated.beadAppearance == .standard,
               "Build 1 migration keeps the original polished onyx oval beads")

        let beforeWidget = try widget.snapshot()
        let afterWidget = try widget.increment(expectedDhikrID: beforeWidget.selectedID, expectedGeneration: beforeWidget.generation)
        assert(afterWidget.count == 18 && !afterWidget.needsOpenApp)
        let secondLaunch = try RoseryStore(repository: appRepository, legacyData: legacy)
        assert(secondLaunch.progress.count == 18, "A later launch must never reimport build 1's stale count")

        // These UI adapters deliberately hold stale snapshots while another process changes the file.
        app.updatePreferences { $0.haptics = true }
        app.increment()
        secondLaunch.toggleBookmark(try require(DhikrLibrary.reading(id: "healing")))
        var merged = try require(widget.readState())
        assert(merged.progress.count == 19, "Preferences and bookmark saves must merge the latest widget count")
        assert(merged.preferences.haptics && merged.bookmarks.contains("healing"))
        assert(merged.sessions.count == 1 && merged.sessions[0].id == sessionID)

        let staleRound = try widget.snapshot()
        app.resetCounter(target: 33)
        let reset = try widget.snapshot()
        assert(reset.count == 0 && reset.generation != staleRound.generation)
        let rejectedRound = try widget.increment(expectedDhikrID: staleRound.selectedID, expectedGeneration: staleRound.generation)
        assert(rejectedRound.count == 0, "A tap rendered before reset cannot count in the next round")
        app.select(try require(DhikrLibrary.reading(id: "alhamdulillah")))
        let rejectedSelection = try widget.increment(expectedDhikrID: reset.selectedID, expectedGeneration: reset.generation)
        assert(rejectedSelection.selectedID == "alhamdulillah" && rejectedSelection.count == 1)
        app.select(DhikrLibrary.primary)
        let rejectedReturn = try widget.increment(expectedDhikrID: reset.selectedID, expectedGeneration: reset.generation)
        assert(rejectedReturn.count == 0, "Leaving and returning to a phrase invalidates an old widget action")

        // Independent OS processes, each with its own repository/file descriptor, stress the lock.
        app.resetCounter(target: 1_000)
        let concurrent = try widget.snapshot()
        let workers = try startWidgetWorkers(directory: directory, snapshot: concurrent, workers: 4, increments: 50)
        for index in 0..<37 {
            app.increment()
            app.updatePreferences { $0.largeArabic = index.isMultiple(of: 2) }
            app.markRecitation(for: try require(DhikrLibrary.reading(id: "healing")))
        }
        try waitForWorkers(workers)
        merged = try require(widget.readState())
        assert(merged.progress.count == 237, "No app or widget increment can be lost under concurrent writes")
        assert(merged.preferences.haptics && merged.preferences.largeArabic)
        assert(merged.bookmarks.contains("al-ikhlas") && merged.bookmarks.contains("healing"))
        assert(merged.readingCounts["healing"] == 1 && merged.sessions.count == 1)
        app.refreshFromShared()
        assert(app.progress.count == 237, "Foreground refresh must observe widget-only increments")

        // Racing the final repetition must create one history record, even with many queued taps.
        app.resetCounter(target: 33)
        for _ in 0..<32 { app.increment(now: date) }
        let lastTap = try widget.snapshot()
        let finishers = try startWidgetWorkers(directory: directory, snapshot: lastTap, workers: 6, increments: 3)
        app.increment(now: date)
        try waitForWorkers(finishers)
        merged = try require(widget.readState())
        assert(merged.progress.count == 33 && merged.sessions.count == 2)
        assert(merged.sessions.filter { $0.dhikrID == "subhanallah" }.count == 1)
        let completedSnapshot = try widget.snapshot()
        assert(completedSnapshot.nextAfterPrayerID == "alhamdulillah")
        app.refreshFromShared()
        app.undo()
        merged = try require(widget.readState())
        assert(merged.progress.count == 32 && merged.sessions.count == 1)
        assert(merged.sessions[0].id == sessionID, "Undo removes only the current round's history")
        app.increment()
        app.beginNextAfterPrayer()
        let nextPhrase = try widget.snapshot()
        assert(nextPhrase.selectedID == "alhamdulillah" && nextPhrase.count == 0 && nextPhrase.target == 33)
        let afterProgression = try require(widget.readState())
        assert(afterProgression.sessions.count == 2)

        // Never repair shared corruption by overwriting it with an old local snapshot.
        let stateURL = directory.appendingPathComponent("state-v2.json")
        let damaged = Data("unreadable shared state".utf8)
        try damaged.write(to: stateURL, options: .atomic)
        do {
            _ = try appRepository.initializeApp(legacyData: legacy)
            assertionFailure("A corrupt shared file must be reported, not replaced")
        } catch { }
        let stillDamaged = try Data(contentsOf: stateURL)
        assert(stillDamaged == damaged)
    }

    private static func startWidgetWorkers(directory: URL, snapshot: TasbihSnapshot, workers: Int, increments: Int) throws -> [Process] {
        try (0..<workers).map { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--widget-worker", directory.path, snapshot.selectedID, snapshot.generation, String(increments)]
            try process.run()
            return process
        }
    }

    private static func waitForWorkers(_ workers: [Process]) throws {
        for worker in workers {
            worker.waitUntilExit()
            guard worker.terminationStatus == 0 else { throw CheckError.workerFailed }
        }
    }

    private static func runWidgetWorker() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6, let iterations = Int(arguments[5]) else { throw CheckError.missingFixture }
        let repository = TasbihRepository(storage: TasbihFileStorage(directory: URL(fileURLWithPath: arguments[2])))
        for _ in 0..<iterations {
            _ = try repository.increment(expectedDhikrID: arguments[3], expectedGeneration: arguments[4])
        }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckError.missingFixture }
        return value
    }

    enum CheckError: Error { case missingFixture, workerFailed }
}
