import Foundation
import Darwin

nonisolated enum TasbihShared {
    static let appGroupID = "group.mujhtech.rosery"
    static let widgetKind = "RoseryTasbihWidget"
    static let legacyStorageKey = "rosery.saved-state.v1"
}

nonisolated enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// A shared visual preference; changing it never starts or alters a counting round.
nonisolated struct BeadAppearance: Codable, Equatable, Sendable {
    enum Material: String, Codable, CaseIterable, Identifiable, Sendable {
        case polished, matte, wood
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Color: String, Codable, CaseIterable, Identifiable, Sendable {
        case onyx, ivory, amber, olive, rose, ocean
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Shape: String, Codable, CaseIterable, Identifiable, Sendable {
        case oval, round, faceted
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var material = Material.polished
    var color = Color.onyx
    var shape = Shape.oval

    static let standard = BeadAppearance()
}

nonisolated struct ReadingPreferences: Codable, Equatable, Sendable {
    var haptics = true
    var transliteration = true
    var largeArabic = false
    var appearance = AppAppearance.system
}

nonisolated struct CounterProgress: Codable, Equatable, Sendable {
    var count = 0
    var target: Int
    var completedSessionID: UUID?
    var generation = UUID()
    var isComplete: Bool { count >= target }

    init(count: Int = 0, target: Int, completedSessionID: UUID? = nil, generation: UUID = UUID()) {
        self.count = count
        self.target = target
        self.completedSessionID = completedSessionID
        self.generation = generation
    }

    private enum CodingKeys: String, CodingKey {
        case count, target, completedSessionID, generation
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        count = try values.decode(Int.self, forKey: .count)
        target = try values.decode(Int.self, forKey: .target)
        completedSessionID = try values.decodeIfPresent(UUID.self, forKey: .completedSessionID)
        // Build 1 did not persist a round token. App migration writes this token once.
        generation = try values.decodeIfPresent(UUID.self, forKey: .generation) ?? UUID()
    }
}

nonisolated struct DhikrSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let dhikrID: String
    let count: Int
    let date: Date
}

/// The codec retains build 1's field names so local progress migrates without loss.
nonisolated struct TasbihState: Codable, Equatable, Sendable {
    var schemaVersion = 3
    var selectedID = DhikrLibrary.primary.id
    var bookmarks: Set<String> = []
    var counters: [String: CounterProgress] = [:]
    var readingCounts: [String: Int] = [:]
    var sessions: [DhikrSession] = []
    var preferences = ReadingPreferences()
    var beadAppearance = BeadAppearance.standard
    var syncRevision: UInt64 = 0
    var syncEpoch = UUID()
    var watchSequences: [String: Int] = [:]
    var watchRejections: [String: [Int]] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, selectedID, bookmarks, counters, readingCounts, sessions, preferences, beadAppearance
        case syncRevision, syncEpoch, watchSequences, watchRejections
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= 3 else { throw TasbihStorageError.unsupportedStateVersion }
        selectedID = try values.decode(String.self, forKey: .selectedID)
        bookmarks = try values.decode(Set<String>.self, forKey: .bookmarks)
        counters = try values.decode([String: CounterProgress].self, forKey: .counters)
        readingCounts = try values.decode([String: Int].self, forKey: .readingCounts)
        sessions = try values.decode([DhikrSession].self, forKey: .sessions)
        preferences = try values.decode(ReadingPreferences.self, forKey: .preferences)
        beadAppearance = try values.decodeIfPresent(BeadAppearance.self, forKey: .beadAppearance) ?? .standard
        syncRevision = try values.decodeIfPresent(UInt64.self, forKey: .syncRevision) ?? 0
        syncEpoch = try values.decodeIfPresent(UUID.self, forKey: .syncEpoch) ?? UUID()
        watchSequences = try values.decodeIfPresent([String: Int].self, forKey: .watchSequences) ?? [:]
        watchRejections = try values.decodeIfPresent([String: [Int]].self, forKey: .watchRejections) ?? [:]
    }

    var selectedDhikr: Dhikr { DhikrLibrary.reading(id: selectedID) ?? DhikrLibrary.primary }
    var progress: CounterProgress {
        counters[selectedID] ?? CounterProgress(target: selectedDhikr.repetitions ?? 33)
    }

    var nextAfterPrayer: Dhikr? {
        guard progress.isComplete, progress.target == selectedDhikr.repetitions else { return nil }
        switch selectedID {
        case "subhanallah": return DhikrLibrary.reading(id: "alhamdulillah")
        case "alhamdulillah": return DhikrLibrary.reading(id: "allahu-akbar")
        default: return nil
        }
    }

    mutating func normalize() {
        if DhikrLibrary.reading(id: selectedID)?.isCounterPhrase != true {
            selectedID = DhikrLibrary.primary.id
        }
        for (id, var progress) in counters {
            progress.target = min(max(progress.target, 1), 10_000)
            progress.count = min(max(progress.count, 0), progress.target)
            counters[id] = progress
        }
        if counters[selectedID] == nil {
            counters[selectedID] = CounterProgress(target: selectedDhikr.repetitions ?? 33)
        }
    }

    func matches(_ expectedID: String, generation: String) -> Bool {
        selectedID == expectedID && progress.generation.uuidString == generation
    }

    mutating func increment(expectedID: String, generation: String, now: Date) {
        guard matches(expectedID, generation: generation), !progress.isComplete else { return }
        var next = progress
        next.count += 1
        recordCompletion(for: &next, now: now)
        counters[selectedID] = next
    }

    mutating func undo(expectedID: String, generation: String) {
        guard matches(expectedID, generation: generation), progress.count > 0 else { return }
        var next = progress
        if let completedID = next.completedSessionID {
            sessions.removeAll { $0.id == completedID }
            next.completedSessionID = nil
        }
        next.count -= 1
        counters[selectedID] = next
    }

    mutating func select(_ dhikr: Dhikr) {
        guard dhikr.isCounterPhrase else { return }
        let changedSelection = selectedID != dhikr.id
        selectedID = dhikr.id
        var next = counters[dhikr.id] ?? CounterProgress(target: dhikr.repetitions ?? 33)
        // A widget showing a previous selection must not affect a later visit to it.
        if changedSelection { next.generation = UUID() }
        counters[dhikr.id] = next
    }

    /// Retarget the current round without discarding counts or counting one round twice.
    @discardableResult
    mutating func setTarget(_ target: Int, expectedID: String, generation: String, now: Date) -> Bool {
        guard matches(expectedID, generation: generation) else { return false }
        let target = min(max(target, 1), 10_000)
        guard target >= progress.count else { return false }
        guard target != progress.target else { return true }

        var next = progress
        next.target = target
        // Both a widget tap and another editor must refer to this target's version of the round.
        next.generation = UUID()
        if let completedID = next.completedSessionID {
            sessions.removeAll { $0.id == completedID }
            next.completedSessionID = nil
        }
        recordCompletion(for: &next, now: now)
        counters[selectedID] = next
        return true
    }

    @discardableResult
    mutating func resetCounter(target: Int?, expectedID: String, generation: String) -> Bool {
        guard matches(expectedID, generation: generation) else { return false }
        counters[selectedID] = CounterProgress(target: min(max(target ?? progress.target, 1), 10_000))
        return true
    }

    mutating func beginNextAfterPrayer(expectedID: String, generation: String) {
        guard matches(expectedID, generation: generation), let next = nextAfterPrayer else { return }
        // Selection and new round are one transaction, never an observable half-transition.
        selectedID = next.id
        counters[next.id] = CounterProgress(target: next.repetitions ?? 33)
    }

    func readingCount(for dhikr: Dhikr) -> Int {
        min(max(readingCounts[dhikr.id, default: 0], 0), dhikr.repetitions ?? 1)
    }

    private mutating func recordCompletion(for progress: inout CounterProgress, now: Date) {
        guard progress.isComplete, progress.completedSessionID == nil else { return }
        let session = DhikrSession(id: UUID(), dhikrID: selectedID, count: progress.count, date: now)
        progress.completedSessionID = session.id
        sessions.insert(session, at: 0)
        sessions = Array(sessions.prefix(100))
    }
}

nonisolated struct TasbihSnapshot: Equatable, Sendable {
    let needsOpenApp: Bool
    let selectedID: String
    let title: String
    let arabic: String
    let count: Int
    let target: Int
    let generation: String
    let nextAfterPrayerID: String?
    let beadAppearance: BeadAppearance
    var isComplete: Bool { !needsOpenApp && count >= target }

    init(state: TasbihState?) {
        let dhikr = state?.selectedDhikr ?? DhikrLibrary.primary
        needsOpenApp = state == nil
        selectedID = dhikr.id
        title = dhikr.title
        arabic = dhikr.arabic
        count = state?.progress.count ?? 0
        target = state?.progress.target ?? dhikr.repetitions ?? 33
        generation = state?.progress.generation.uuidString ?? ""
        nextAfterPrayerID = state?.nextAfterPrayer?.id
        beadAppearance = state?.beadAppearance ?? .standard
    }

    static let needsApp = TasbihSnapshot(state: nil)
    static let preview: TasbihSnapshot = {
        var state = TasbihState()
        state.normalize()
        state.counters[state.selectedID]?.count = 12
        return TasbihSnapshot(state: state)
    }()
}

nonisolated enum TasbihStorageError: Error {
    case appGroupUnavailable
    case notInitialized
    case unsupportedStateVersion
    case syncRevisionExhausted
    case lockFailed(Int32)
}

/// Both adapters must serialize the entire read/modify/write transaction.
nonisolated protocol TasbihStorage: Sendable {
    func withData<Result>(_ operation: (inout Data?) throws -> Result) throws -> Result
}

/// Uses a separate stable lock file because atomic replacement changes the data file's inode.
nonisolated final class TasbihFileStorage: TasbihStorage {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    func withData<Result>(_ operation: (inout Data?) throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("state.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TasbihStorageError.lockFailed(errno) }
        defer { Darwin.close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw TasbihStorageError.lockFailed(errno) }
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        let url = directory.appendingPathComponent("state-v2.json")
        var data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            data = nil
        }
        let original = data
        let result = try operation(&data)
        if let data, data != original {
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtectionUntilFirstUserAuthentication)
            #endif
            try data.write(to: url, options: options)
        }
        return result
    }
}

/// Pure domain operations shared by the app and its App Intent. Never caches saved state.
nonisolated final class TasbihRepository: Sendable {
    private let storage: any TasbihStorage

    init(storage: any TasbihStorage) { self.storage = storage }

    static func appGroup() throws -> TasbihRepository {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TasbihShared.appGroupID) else {
            throw TasbihStorageError.appGroupUnavailable
        }
        return TasbihRepository(storage: TasbihFileStorage(directory: container.appendingPathComponent("Tasbih", isDirectory: true)))
    }

    /// Only the app calls this. A widget cannot seed a new state ahead of legacy migration.
    @discardableResult
    func initializeApp(legacyData: Data?, recoverMalformedLocalState: Bool = false) throws -> TasbihState {
        try storage.withData { data in
            if let existing = data {
                do {
                    var state = try JSONDecoder().decode(TasbihState.self, from: existing)
                    state.normalize()
                    data = try JSONEncoder().encode(state)
                    return state
                } catch {
                    // Only the explicit in-memory/local-defaults adapter permits old recovery behavior.
                    // An unreadable shared file is never replaced with stale legacy data.
                    guard recoverMalformedLocalState else { throw error }
                }
            }
            var state = legacyData.flatMap { try? JSONDecoder().decode(TasbihState.self, from: $0) } ?? TasbihState()
            state.normalize()
            data = try JSONEncoder().encode(state)
            return state
        }
    }

    func readState() throws -> TasbihState? {
        try storage.withData { data in
            try data.map { try JSONDecoder().decode(TasbihState.self, from: $0) }
        }
    }

    func snapshot() throws -> TasbihSnapshot { TasbihSnapshot(state: try readState()) }

    /// No initialization, no stale cache, and no writes when an action cannot apply.
    @discardableResult
    func update(_ operation: (inout TasbihState) -> Void) throws -> TasbihState? {
        try storage.withData { data in
            guard let existing = data else { return nil }
            var state = try JSONDecoder().decode(TasbihState.self, from: existing)
            let original = state
            operation(&state)
            if state != original {
                guard original.syncRevision < UInt64.max else { throw TasbihStorageError.syncRevisionExhausted }
                state.syncRevision = original.syncRevision + 1
                data = try JSONEncoder().encode(state)
            }
            return state
        }
    }

    func increment(expectedDhikrID: String, expectedGeneration: String, now: Date = .now) throws -> TasbihSnapshot {
        let state = try update { state in
            state.increment(expectedID: expectedDhikrID, generation: expectedGeneration, now: now)
        }
        return TasbihSnapshot(state: state)
    }
}
