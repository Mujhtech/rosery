import Foundation

@main
struct LiveActivityChecks {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = TasbihState()
        state.normalize()
        state.counters[state.selectedID]?.count = 12
        let snapshot = TasbihSnapshot(state: state)
        let attributes = TasbihActivityAttributes(selectedID: snapshot.selectedID,
                                                  generation: snapshot.generation, startedAt: now)
        let content = TasbihActivityPolicy.content(for: snapshot, now: now)

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(TasbihActivityAttributes.ContentState.self, from: encoded)
        assert(decoded == content)
        assert(TasbihActivityPolicy.fitsPayload(attributes: attributes, content: content))
        assert(content.staleDate == now.addingTimeInterval(1_800))
        assert(content.acceptsCount(at: now.addingTimeInterval(1_799)))
        assert(!content.acceptsCount(at: now.addingTimeInterval(1_800)), "The exact stale boundary is read-only")
        assert(!TasbihActivityPolicy.ended(content, now: now).acceptsCount(at: now))

        for dhikr in DhikrLibrary.readings where dhikr.isCounterPhrase {
            var fixture = TasbihState()
            fixture.select(dhikr)
            let value = TasbihSnapshot(state: fixture)
            let record = TasbihActivityPolicy.content(for: value, now: now)
            assert(TasbihActivityPolicy.fitsPayload(attributes: attributes, content: record), dhikr.title)
        }
        var oversized = content
        oversized.arabic = String(repeating: "ذكر", count: 2_000)
        assert(!TasbihActivityPolicy.fitsPayload(attributes: attributes, content: oversized))

        assert(TasbihActivityPolicy.decision(attributes: attributes, current: content, snapshot: snapshot,
                                             now: now.addingTimeInterval(60), refreshStale: false) == .unchanged)
        let staleNow = now.addingTimeInterval(1_801)
        assert(TasbihActivityPolicy.decision(attributes: attributes, current: content, snapshot: snapshot,
                                             now: staleNow, refreshStale: false) == .unchanged,
               "A background refresh must not silently make an inactive session interactive")
        let resumed = TasbihActivityPolicy.content(for: snapshot, now: staleNow)
        assert(TasbihActivityPolicy.decision(attributes: attributes, current: content, snapshot: snapshot,
                                             now: staleNow, refreshStale: true) == .update(resumed))

        var latest = state
        latest.increment(expectedID: snapshot.selectedID, generation: snapshot.generation, now: now)
        let latestSnapshot = TasbihSnapshot(state: latest)
        assert(TasbihActivityPolicy.decision(attributes: attributes, current: content, snapshot: latestSnapshot,
                                             now: now, refreshStale: false)
            == .update(TasbihActivityPolicy.content(for: latestSnapshot, now: now)))
        latest.undo(expectedID: snapshot.selectedID, generation: snapshot.generation)
        assert(TasbihSnapshot(state: latest).count == 12)

        var completed = state
        completed.counters[completed.selectedID]?.count = snapshot.target
        let completedSnapshot = TasbihSnapshot(state: completed)
        let terminal = TasbihActivityPolicy.content(for: completedSnapshot, now: now)
        assert(terminal.phase == .complete && terminal.isComplete && !terminal.acceptsCount(at: now))
        assert(TasbihActivityPolicy.decision(attributes: attributes, current: content, snapshot: completedSnapshot,
                                             now: now, refreshStale: false) == .end(terminal))
        let ended = TasbihActivityPolicy.ended(content, now: now)
        assert(TasbihActivityPolicy.decision(attributes: attributes, current: terminal, snapshot: snapshot,
                                             now: now, refreshStale: true)
            == .end(TasbihActivityPolicy.ended(terminal, now: now)), "Undo cannot restart an ended activity")
        assert(TasbihActivityPolicy.decision(attributes: attributes, current: content, snapshot: .needsApp,
                                             now: now, refreshStale: false) == .end(ended))

        for changedRound in [reset(state), retarget(state), selectAnother(state)] {
            assert(TasbihActivityPolicy.decision(attributes: attributes, current: content,
                                                 snapshot: TasbihSnapshot(state: changedRound), now: now,
                                                 refreshStale: true) == .end(ended))
        }

        try await checkAtomicIntentMutations(now: now)
        print("Live Activity checks passed: fixtures, payloads, stale boundaries, terminal decisions, and atomic intent guards.")
    }

    private static func reset(_ original: TasbihState) -> TasbihState {
        var state = original
        state.resetCounter(target: nil, expectedID: state.selectedID, generation: state.progress.generation.uuidString)
        return state
    }

    private static func retarget(_ original: TasbihState) -> TasbihState {
        var state = original
        state.setTarget(99, expectedID: state.selectedID, generation: state.progress.generation.uuidString, now: .now)
        return state
    }

    private static func selectAnother(_ original: TasbihState) -> TasbihState {
        var state = original
        state.select(DhikrLibrary.readings.first { $0.isCounterPhrase && $0.id != original.selectedID }!)
        return state
    }

    private static func checkAtomicIntentMutations(now: Date) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-live-activity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TasbihRepository(storage: TasbihFileStorage(directory: directory))
        let initial = try repository.initializeApp(legacyData: nil)
        let id = initial.selectedID
        let generation = initial.progress.generation.uuidString
        let added = try TasbihActivityMutation.apply(.increment, repository: repository, expectedID: id,
                                                     generation: generation, now: now)
        assert(added.changed && added.snapshot.count == 1)
        let undone = try TasbihActivityMutation.apply(.undo, repository: repository, expectedID: id,
                                                      generation: generation, now: now)
        assert(undone.changed && undone.snapshot.count == 0)
        let noOp = try TasbihActivityMutation.apply(.undo, repository: repository, expectedID: id,
                                                    generation: generation, now: now)
        assert(!noOp.changed && noOp.snapshot.count == 0)
        _ = try repository.update { state in
            state.resetCounter(target: 1, expectedID: id, generation: generation)
        }
        let stale = try TasbihActivityMutation.apply(.increment, repository: repository, expectedID: id,
                                                     generation: generation, now: now)
        assert(!stale.changed && stale.snapshot.count == 0, "An old Activity button cannot affect a new round")
        let current = try repository.snapshot()
        let complete = try TasbihActivityMutation.apply(.increment, repository: repository, expectedID: id,
                                                        generation: current.generation, now: now)
        assert(complete.changed && complete.snapshot.isComplete)
        let duplicate = try TasbihActivityMutation.apply(.increment, repository: repository, expectedID: id,
                                                         generation: current.generation, now: now)
        assert(!duplicate.changed && duplicate.snapshot.count == 1)
        let saved = try repository.readState()
        assert(saved?.sessions.count == 1)
        let delayedUndo = try TasbihActivityMutation.apply(.undo, repository: repository, expectedID: id,
                                                           generation: current.generation,
                                                           requiresIncompleteRound: true, now: now)
        assert(!delayedUndo.changed && delayedUndo.snapshot.isComplete,
               "A Live Activity Undo queued before completion cannot reopen the completed round")

        _ = try repository.update { state in
            state.resetCounter(target: 100, expectedID: id, generation: current.generation)
        }
        let rapidRound = try repository.snapshot()
        let expectedDelta = try await withThrowingTaskGroup(of: Int.self, returning: Int.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let increment = index.isMultiple(of: 2)
                    let result = try TasbihActivityMutation.apply(increment ? .increment : .undo,
                                                                 repository: repository, expectedID: id,
                                                                 generation: rapidRound.generation, now: now)
                    return result.changed ? (increment ? 1 : -1) : 0
                }
            }
            var total = 0
            for try await value in group { total += value }
            return total
        }
        let rapidResult = try repository.snapshot()
        assert(rapidResult.count == expectedDelta && rapidResult.count >= 0,
               "Fast +1/Undo actions must reflect only committed atomic mutations")

        let unavailable = TasbihRepository(storage: RejectedActivityStorage())
        do {
            _ = try TasbihActivityMutation.apply(.increment, repository: unavailable, expectedID: id,
                                                 generation: current.generation, now: now)
            assertionFailure("A persistence error must not be reported as a successful count")
        } catch { }
    }
}

private nonisolated struct RejectedActivityStorage: TasbihStorage {
    enum Failure: Error { case unavailable }
    func withData<Result>(_ operation: (inout Data?) throws -> Result) throws -> Result { throw Failure.unavailable }
}
