import Foundation
import Observation

/// An adapter for isolated tests/previews and the app's old local persistence domain.
/// Production app/widget sharing uses TasbihFileStorage's interprocess lock instead.
nonisolated final class TasbihDefaultsStorage: TasbihStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) { self.defaults = defaults }

    func withData<Result>(_ operation: (inout Data?) throws -> Result) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        var data = defaults.data(forKey: TasbihShared.legacyStorageKey)
        let original = data
        let result = try operation(&data)
        if data != original { defaults.set(data, forKey: TasbihShared.legacyStorageKey) }
        return result
    }
}

@MainActor
@Observable
final class RoseryStore {
    private var state: TasbihState
    private(set) var persistenceError: String?
    @ObservationIgnored private let repository: TasbihRepository
    @ObservationIgnored var onCounterChange: (() -> Void)?

    /// An explicit defaults argument keeps previews and executable checks isolated.
    /// Normal launches migrate build 1's local value only if the shared file is absent.
    init(defaults: UserDefaults? = nil) {
        let legacy = defaults ?? .standard
        let selectedRepository: TasbihRepository
        let localAdapter: Bool
        if let defaults {
            selectedRepository = TasbihRepository(storage: TasbihDefaultsStorage(defaults: defaults))
            localAdapter = true
        } else if let shared = try? TasbihRepository.appGroup() {
            selectedRepository = shared
            localAdapter = false
        } else {
            // Keep build 1 functional if a development install lacks the App Group entitlement.
            selectedRepository = TasbihRepository(storage: TasbihDefaultsStorage(defaults: legacy))
            localAdapter = true
        }
        repository = selectedRepository
        var initial = TasbihState()
        initial.normalize()
        state = initial
        do {
            state = try repository.initializeApp(legacyData: legacy.data(forKey: TasbihShared.legacyStorageKey),
                                                 recoverMalformedLocalState: localAdapter)
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    /// Test seam for separate app/widget clients of the same transactional file store.
    init(repository: TasbihRepository, legacyData: Data? = nil) throws {
        self.repository = repository
        state = try repository.initializeApp(legacyData: legacyData)
    }

    var selectedDhikr: Dhikr { state.selectedDhikr }
    var progress: CounterProgress { state.progress }
    var preferences: ReadingPreferences { state.preferences }
    var beadAppearance: BeadAppearance { state.beadAppearance }
    var tasbihSnapshot: TasbihSnapshot { TasbihSnapshot(state: state) }
    var sessions: [DhikrSession] { state.sessions }
    var bookmarks: [Dhikr] { DhikrLibrary.readings.filter { state.bookmarks.contains($0.id) } }
    var isPersonalTarget: Bool { progress.target != selectedDhikr.repetitions }
    var nextAfterPrayer: Dhikr? { state.nextAfterPrayer }
    var watchSyncRepository: TasbihRepository { repository }

    func refreshFromShared() {
        do {
            if let latest = try repository.readState() { state = latest }
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func isBookmarked(_ dhikr: Dhikr) -> Bool { state.bookmarks.contains(dhikr.id) }

    func toggleBookmark(_ dhikr: Dhikr) {
        update { state in
            if state.bookmarks.contains(dhikr.id) { state.bookmarks.remove(dhikr.id) }
            else { state.bookmarks.insert(dhikr.id) }
        }
    }

    func select(_ dhikr: Dhikr) {
        update(counterChange: true) { $0.select(dhikr) }
    }

    func increment(now: Date = .now) {
        let id = state.selectedID
        let generation = progress.generation.uuidString
        update(counterChange: true) { $0.increment(expectedID: id, generation: generation, now: now) }
    }

    func undo() {
        let id = state.selectedID
        let generation = progress.generation.uuidString
        update(counterChange: true) { $0.undo(expectedID: id, generation: generation) }
    }

    /// An editor supplies its captured context so a save cannot retarget a different round.
    @discardableResult
    func setTarget(_ target: Int, expectedID: String? = nil, expectedGeneration: UUID? = nil, now: Date = .now) -> Bool {
        let id = expectedID ?? state.selectedID
        let generation = (expectedGeneration ?? progress.generation).uuidString
        var accepted = false
        let persisted = update(counterChange: true) {
            accepted = $0.setTarget(target, expectedID: id, generation: generation, now: now)
        }
        return persisted && accepted
    }

    @discardableResult
    func resetCounter(target: Int? = nil, expectedID: String? = nil, expectedGeneration: UUID? = nil) -> Bool {
        let id = expectedID ?? state.selectedID
        let generation = (expectedGeneration ?? progress.generation).uuidString
        var accepted = false
        let persisted = update(counterChange: true) {
            accepted = $0.resetCounter(target: target, expectedID: id, generation: generation)
        }
        return persisted && accepted
    }

    func beginNextAfterPrayer() {
        let id = state.selectedID
        let generation = progress.generation.uuidString
        update(counterChange: true) { $0.beginNextAfterPrayer(expectedID: id, generation: generation) }
    }

    func readingCount(for dhikr: Dhikr) -> Int { state.readingCount(for: dhikr) }

    func markRecitation(for dhikr: Dhikr) {
        update { state in
            state.readingCounts[dhikr.id] = min(state.readingCount(for: dhikr) + 1, dhikr.repetitions ?? 1)
        }
    }

    func resetReading(_ dhikr: Dhikr) {
        update { $0.readingCounts[dhikr.id] = 0 }
    }

    func updatePreferences(_ operation: (inout ReadingPreferences) -> Void) {
        update { operation(&$0.preferences) }
    }

    @discardableResult
    func updateBeadAppearance(_ operation: (inout BeadAppearance) -> Void) -> Bool {
        update(counterChange: true) { operation(&$0.beadAppearance) }
    }

    @discardableResult
    private func update(counterChange: Bool = false, _ operation: (inout TasbihState) -> Void) -> Bool {
        do {
            guard let latest = try repository.update(operation) else { throw TasbihStorageError.notInitialized }
            let previous = state
            state = latest
            persistenceError = nil
            if counterChange, previous != latest { onCounterChange?() }
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }
}
