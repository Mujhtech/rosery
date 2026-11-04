import Dispatch
import Foundation

/// Rejects a commit after domain work, using the real locked temporary-file storage underneath.
nonisolated final class WatchChecksFailableStorage: TasbihStorage, @unchecked Sendable {
    private let storage: TasbihFileStorage
    private let lock = NSLock()
    private var rejectsWrites = false

    init(directory: URL) { storage = TasbihFileStorage(directory: directory) }

    func rejectWrites(_ reject: Bool) {
        lock.lock()
        rejectsWrites = reject
        lock.unlock()
    }

    func withData<Result>(_ operation: (inout Data?) throws -> Result) throws -> Result {
        try storage.withData { data in
            var proposed = data
            let result = try operation(&proposed)
            lock.lock()
            let reject = rejectsWrites
            lock.unlock()
            if reject && proposed != data { throw Failure.commitRejected }
            data = proposed
            return result
        }
    }

    private enum Failure: Error { case commitRejected }
}

nonisolated final class WatchChecksErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ error: any Error) {
        lock.lock()
        messages.append(String(describing: error))
        lock.unlock()
    }

    func requireEmpty() {
        lock.lock()
        defer { lock.unlock() }
        precondition(messages.isEmpty, "Concurrent workers failed: \(messages)")
    }
}

/// Pure protocol and persistence checks; no WatchConnectivity session or real app data is used.
@main
nonisolated struct WatchSyncChecks {
    private static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func main() throws {
        try checkOfflineProjectionAndReplay()
        try checkQueuedRoundTransitions()
        try checkGapsAndStaleRounds()
        try checkConcurrentPhoneAndWatchDeltas()
        try checkFailedCommits()
        try checkEpochAndRevisionHandling()
        try checkCodecsAndBounds()
        print("PASS: durable Watch identity/outbox; offline projection; replay deduplication and sequence gaps; deterministic queued round transitions; stale-round rejection; concurrent phone/Watch deltas; atomic failed commits; legacy codecs; packet bounds; revision and phone-reinstall epoch handling.")
    }

    private static func checkOfflineProjectionAndReplay() throws {
        try withDirectory("offline") { root in
            let phone = try phoneRepository(at: root.appendingPathComponent("phone"), target: 100)
            let initial = try require(phone.readState())
            let watchURL = root.appendingPathComponent("watch")
            let watch = WatchReplicaRepository(storage: TasbihFileStorage(directory: watchURL))
            let first = try watch.load()
            let reloaded = try WatchReplicaRepository(storage: TasbihFileStorage(directory: watchURL)).load()
            precondition(first.deviceID == reloaded.deviceID, "The first device UUID must be committed before a phone reply")
            precondition(first.confirmed == nil && first.projected == nil)
            try expect(.waitingForPhone) { var value = first; try value.enqueue(.increment, now: date) }
            _ = try watch.update { precondition($0.receive(initial)) }
            for _ in 0..<5 { _ = try watch.update { try $0.enqueue(.increment, now: date) } }
            let queued = try watch.update { try $0.enqueue(.undo, now: date) }
            precondition(queued.pending.count == 6 && queued.lastSequence == 6)
            precondition(queued.projected?.progress.count == 4 && queued.confirmed?.progress.count == 0)
            let unchangedPhone = try require(phone.readState())
            precondition(unchangedPhone.progress.count == 0, "Offline projection must never overwrite phone state")
            let relaunched = try WatchReplicaRepository(storage: TasbihFileStorage(directory: watchURL)).load()
            precondition(relaunched == queued, "An offline Watch relaunch must retain its exact outbox and device ID")

            let accepted = try deliver(queued.batch, to: phone)
            precondition(accepted.progress.count == 4 && accepted.watchSequences[queued.deviceID.uuidString] == 6)
            let duplicate = try deliver(queued.batch, to: phone)
            precondition(duplicate == accepted, "A repeated transport delivery must not count or revise state twice")
            let acknowledged = try watch.update { precondition($0.receive(accepted)) }
            precondition(acknowledged.pending.isEmpty && acknowledged.projected?.progress.count == 4)
            precondition(!acknowledged.hasConflictNotice)
        }
    }

    private static func checkQueuedRoundTransitions() throws {
        try withDirectory("transitions") { root in
            let phone = try phoneRepository(at: root)
            let initial = try require(phone.readState())
            var watch = WatchReplica()
            precondition(watch.receive(initial))
            let actions: [WatchCounterAction] = [
                .increment, .increment, .target(10), .increment, .restart(5), .increment,
                .select("alhamdulillah"), .increment, .select("subhanallah"), .target(1),
                .select("alhamdulillah"), .restart(33)
            ] + Array(repeating: .increment, count: 33) + [.next, .increment, .increment]
            for (index, action) in actions.enumerated() {
                try watch.enqueue(action, now: date.addingTimeInterval(Double(index)))
            }
            precondition(watch.pending.count == actions.count && actions.count < WatchReplica.batchLimit)
            let projected = try require(watch.projected)
            precondition(projected.selectedID == "allahu-akbar" && projected.progress.count == 2 && projected.progress.target == 33)
            precondition(projected.counters["subhanallah"]?.count == 1 && projected.counters["subhanallah"]?.target == 1)
            precondition(projected.counters["alhamdulillah"]?.count == 33)

            var replay = initial
            for operation in watch.pending {
                let previousTarget = replay.progress.target
                precondition(operation.expectedID == replay.selectedID && operation.generation == replay.progress.generation)
                precondition(operation.apply(to: &replay))
                let replacesGeneration: Bool
                switch operation.action {
                case .target(let value): replacesGeneration = value != previousTarget
                case .select(let id): replacesGeneration = id != operation.expectedID
                case .restart, .next: replacesGeneration = true
                default: replacesGeneration = false
                }
                precondition(replay.progress.generation == (replacesGeneration ? operation.replacementGeneration : operation.generation),
                             "Every queued transition must use its transmitted generation on both devices")
            }
            let accepted = try deliver(watch.batch, to: phone)
            precondition(counterSummaries(accepted) == counterSummaries(projected))
            precondition(sessionSummaries(accepted) == sessionSummaries(projected) && accepted.sessions.count == 2)
            let duplicate = try deliver(watch.batch, to: phone)
            precondition(duplicate == accepted, "Replaying completion/next must not create duplicate history or restart rounds")
            precondition(watch.receive(accepted) && watch.pending.isEmpty)

            let beforeInvalid = watch
            for action: WatchCounterAction in [.target(0), .target(1), .restart(0), .select("healing"), .next] {
                try expect(.invalidPayload) { try watch.enqueue(action, now: date) }
                precondition(watch == beforeInvalid, "An invalid command must not consume a sequence or alter the outbox")
            }
        }
    }

    private static func checkGapsAndStaleRounds() throws {
        try withDirectory("gaps") { root in
            let phone = try phoneRepository(at: root)
            let initial = try require(phone.readState())
            var watch = WatchReplica()
            precondition(watch.receive(initial))
            for _ in 0..<3 { try watch.enqueue(.increment, now: date) }
            let originalBatch = watch.batch
            let gap = WatchCounterBatch(deviceID: watch.deviceID, operations: Array(originalBatch.operations.dropFirst()))
            let notAcknowledged = try deliver(gap, to: phone)
            precondition(notAcknowledged == initial, "A missing sequence must not discard or prematurely acknowledge later operations")
            precondition(watch.receive(notAcknowledged) && watch.pending.count == 3)
            let prefix = WatchCounterBatch(deviceID: watch.deviceID, operations: Array(originalBatch.operations.prefix(1)))
            let partial = try deliver(prefix, to: phone)
            precondition(watch.receive(partial) && watch.pending.map(\.sequence) == [2, 3])
            let completed = try deliver(originalBatch, to: phone)
            precondition(completed.progress.count == 3 && completed.watchSequences[watch.deviceID.uuidString] == 3)
            precondition(watch.receive(completed) && watch.pending.isEmpty)

            try watch.enqueue(.increment, now: date)
            try watch.enqueue(.target(100), now: date)
            try watch.enqueue(.increment, now: date)
            _ = try phone.update { state in
                _ = state.resetCounter(target: nil, expectedID: state.selectedID, generation: state.progress.generation.uuidString)
            }
            let reset = try require(phone.readState())
            let rejected = try deliver(watch.batch, to: phone)
            precondition(rejected.progress == reset.progress && rejected.progress.count == 0)
            precondition(rejected.watchRejections[watch.deviceID.uuidString] == [4, 5, 6])
            precondition(watch.receive(rejected) && watch.pending.isEmpty && watch.hasConflictNotice)
            precondition(watch.projected?.progress.count == 0, "A stale offline round must yield to the phone's restarted round")
        }

        try withDirectory("concurrent-retarget") { root in
            let phone = try phoneRepository(at: root)
            let initial = try require(phone.readState())
            var watch = WatchReplica()
            precondition(watch.receive(initial))
            try watch.enqueue(.target(3), now: date)
            try watch.enqueue(.increment, now: date)
            for _ in 0..<5 {
                _ = try phone.increment(expectedDhikrID: initial.selectedID, expectedGeneration: initial.progress.generation.uuidString, now: date)
            }
            let result = try deliver(watch.batch, to: phone)
            precondition(result.progress.count == 5 && result.progress.target == 33,
                         "A Watch target below the newer phone count must not reset phone progress")
            precondition(result.watchRejections[watch.deviceID.uuidString] == [1, 2])
            precondition(watch.receive(result) && watch.hasConflictNotice && watch.projected?.progress.count == 5)
        }
    }

    private static func checkConcurrentPhoneAndWatchDeltas() throws {
        try withDirectory("concurrent") { root in
            let phone = try phoneRepository(at: root, target: 1000)
            let initial = try require(phone.readState())
            var first = WatchReplica()
            var second = WatchReplica()
            precondition(first.receive(initial) && second.receive(initial))
            for _ in 0..<20 { try first.enqueue(.increment, now: date); try second.enqueue(.increment, now: date) }
            let batches = [first.batch, second.batch]
            let errors = WatchChecksErrors()
            DispatchQueue.concurrentPerform(iterations: 6) { worker in
                do {
                    let repository = TasbihRepository(storage: TasbihFileStorage(directory: root))
                    if worker < 2 {
                        for _ in 0..<8 { _ = try deliver(batches[worker], to: repository) }
                    } else {
                        for _ in 0..<25 {
                            _ = try repository.increment(expectedDhikrID: initial.selectedID,
                                                         expectedGeneration: initial.progress.generation.uuidString, now: date)
                        }
                    }
                } catch { errors.append(error) }
            }
            errors.requireEmpty()
            let result = try require(phone.readState())
            precondition(result.progress.count == 140, "Atomic phone/Watch transactions must preserve every distinct increment")
            precondition(result.watchSequences[first.deviceID.uuidString] == 20 && result.watchSequences[second.deviceID.uuidString] == 20)
            precondition(first.receive(result) && second.receive(result))
            precondition(first.pending.isEmpty && second.pending.isEmpty && first.projected?.progress.count == 140)
        }
    }

    private static func checkFailedCommits() throws {
        try withDirectory("failed-writes") { root in
            let phoneURL = root.appendingPathComponent("phone")
            let watchURL = root.appendingPathComponent("watch")
            let phoneStorage = WatchChecksFailableStorage(directory: phoneURL)
            let watchStorage = WatchChecksFailableStorage(directory: watchURL)
            let phone = TasbihRepository(storage: phoneStorage)
            let initial = try phone.initializeApp(legacyData: nil)
            let watch = WatchReplicaRepository(storage: watchStorage)
            _ = try watch.load()
            _ = try watch.update { precondition($0.receive(initial)) }
            for _ in 0..<3 { _ = try watch.update { try $0.enqueue(.increment, now: date) } }
            let queued = try watch.load()
            let phoneBytes = try Data(contentsOf: phoneURL.appendingPathComponent("state-v2.json"))
            let watchBytes = try Data(contentsOf: watchURL.appendingPathComponent("state-v2.json"))

            phoneStorage.rejectWrites(true)
            try expectFailure { _ = try deliver(queued.batch, to: phone) }
            let failedPhone = try require(phone.readState())
            let afterFailure = try Data(contentsOf: phoneURL.appendingPathComponent("state-v2.json"))
            precondition(failedPhone == initial && afterFailure == phoneBytes,
                         "A failed phone commit must persist neither counts nor replay receipts")
            let stillQueued = try watch.load()
            precondition(stillQueued == queued)
            phoneStorage.rejectWrites(false)
            let accepted = try deliver(queued.batch, to: phone)
            precondition(accepted.progress.count == 3)

            watchStorage.rejectWrites(true)
            try expectFailure { _ = try watch.update { precondition($0.receive(accepted)) } }
            let failedWatch = try watch.load()
            let afterWatchFailure = try Data(contentsOf: watchURL.appendingPathComponent("state-v2.json"))
            precondition(failedWatch == queued && afterWatchFailure == watchBytes,
                         "A failed Watch receipt commit must retain every unacknowledged operation")
            let duplicate = try deliver(queued.batch, to: phone)
            precondition(duplicate == accepted)
            watchStorage.rejectWrites(false)
            let acknowledged = try watch.update { precondition($0.receive(accepted)) }
            precondition(acknowledged.pending.isEmpty && acknowledged.projected?.progress.count == 3)
        }
    }

    private static func checkEpochAndRevisionHandling() throws {
        var initial = TasbihState()
        initial.normalize()
        initial.syncRevision = 5
        initial.counters[initial.selectedID]?.count = 2
        var watch = WatchReplica()
        precondition(watch.receive(initial))
        for _ in 0..<3 { try watch.enqueue(.increment, now: date) }
        let originalDevice = watch.deviceID
        var stale = initial
        stale.syncRevision = 4
        stale.counters[stale.selectedID]?.count = 1
        precondition(!watch.receive(stale) && watch.projected?.progress.count == 5)
        var newer = initial
        newer.syncRevision = 6
        newer.counters[newer.selectedID]?.count = 3
        precondition(watch.receive(newer) && watch.projected?.progress.count == 6,
                     "A newer phone snapshot must rebase, then replay, the unacknowledged local delta")
        var impossibleReceipt = newer
        impossibleReceipt.syncRevision = 7
        impossibleReceipt.watchSequences[watch.deviceID.uuidString] = watch.lastSequence + 1
        precondition(!watch.receive(impossibleReceipt) && watch.pending.count == 3)

        var replacementPhone = TasbihState()
        replacementPhone.normalize()
        precondition(replacementPhone.syncEpoch != initial.syncEpoch && replacementPhone.syncRevision == 0)
        precondition(watch.receive(replacementPhone), "A fresh phone epoch must be accepted despite a lower revision")
        precondition(watch.deviceID != originalDevice && watch.lastSequence == 0 && watch.pending.isEmpty)
        precondition(watch.hasConflictNotice && watch.retiredPhoneEpochs.contains(initial.syncEpoch))
        precondition(watch.projected?.syncEpoch == replacementPhone.syncEpoch && watch.projected?.progress.count == 0)
        try watch.enqueue(.increment, now: date)
        precondition(watch.pending.first?.sequence == 1 && !watch.hasConflictNotice)
        var delayedOldPhone = newer
        delayedOldPhone.syncRevision = UInt64.max
        let beforeOldReply = watch
        precondition(!watch.receive(delayedOldPhone) && watch == beforeOldReply,
                     "A delayed retired epoch must never replace the newer phone installation")
        let restored = try JSONDecoder().decode(WatchReplica.self, from: JSONEncoder().encode(watch))
        precondition(restored == watch && restored.retiredPhoneEpochs.contains(initial.syncEpoch))
    }

    private static func checkCodecsAndBounds() throws {
        try withDirectory("codecs") { root in
            var seed = TasbihState()
            seed.normalize()
            seed.counters[seed.selectedID]?.count = 7
            seed.bookmarks = ["al-ikhlas"]
            seed.readingCounts = ["al-ikhlas": 2]
            seed.preferences.haptics = false
            seed.beadAppearance = BeadAppearance(material: .wood, color: .amber, shape: .round)
            var legacy = try require(JSONSerialization.jsonObject(with: JSONEncoder().encode(seed)) as? [String: Any])
            legacy["schemaVersion"] = 2
            for key in ["syncRevision", "syncEpoch", "watchSequences", "watchRejections"] { legacy.removeValue(forKey: key) }
            let legacyData = try JSONSerialization.data(withJSONObject: legacy)
            let decoded = try JSONDecoder().decode(TasbihState.self, from: legacyData)
            precondition(decoded.progress == seed.progress && decoded.bookmarks == seed.bookmarks && decoded.readingCounts == seed.readingCounts)
            precondition(decoded.preferences == seed.preferences && decoded.beadAppearance == seed.beadAppearance)
            precondition(decoded.syncRevision == 0 && decoded.watchSequences.isEmpty && decoded.watchRejections.isEmpty)
            precondition(decoded.schemaVersion == 3, "Legacy state must upgrade before saving the replay ledger")
            try legacyData.write(to: root.appendingPathComponent("state-v2.json"))
            let phone = TasbihRepository(storage: TasbihFileStorage(directory: root))
            let initialized = try phone.initializeApp(legacyData: nil)
            let firstRead = try require(phone.readState())
            let secondRead = try require(phone.readState())
            precondition(initialized.syncEpoch == firstRead.syncEpoch && firstRead.syncEpoch == secondRead.syncEpoch,
                         "The migration-generated epoch must be written once and survive repeated reads")
            let migratedJSON = try require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("state-v2.json"))) as? [String: Any])
            precondition(migratedJSON["schemaVersion"] as? Int == 3,
                         "Schema2 binaries must reject the new ledger rather than dropping unknown receipt fields")

            var future = migratedJSON
            future["schemaVersion"] = 4
            let futureData = try JSONSerialization.data(withJSONObject: future)
            try futureData.write(to: root.appendingPathComponent("state-v2.json"))
            try expectUnsupportedState { _ = try phone.readState() }
            try expectUnsupportedState { _ = try phone.initializeApp(legacyData: legacyData) }
            try expectUnsupportedState { _ = try phone.update { $0.bookmarks.removeAll() } }
            let preservedFuture = try Data(contentsOf: root.appendingPathComponent("state-v2.json"))
            precondition(preservedFuture == futureData, "An unsupported state file must survive reads, migration and rejected mutations verbatim")

            var replica = WatchReplica()
            precondition(replica.receive(initialized))
            try replica.enqueue(.increment, now: date)
            var oldReplica = try require(JSONSerialization.jsonObject(with: JSONEncoder().encode(replica)) as? [String: Any])
            oldReplica.removeValue(forKey: "retiredPhoneEpochs")
            let compatible = try JSONDecoder().decode(WatchReplica.self, from: JSONSerialization.data(withJSONObject: oldReplica))
            precondition(compatible.deviceID == replica.deviceID && compatible.lastSequence == replica.lastSequence && compatible.pending == replica.pending)
            precondition(compatible.confirmed == replica.confirmed && compatible.retiredPhoneEpochs.isEmpty)

            let request = try WatchSyncPacket.request(replica.batch).encoded()
            guard case .request(let decodedBatch) = try WatchSyncPacket.decode(request) else { throw CheckError.unexpectedPacket }
            precondition(decodedBatch == replica.batch)
            let snapshot = try WatchSyncPacket.snapshot(initialized).encoded()
            guard case .snapshot(let decodedState) = try WatchSyncPacket.decode(snapshot) else { throw CheckError.unexpectedPacket }
            precondition(decodedState == initialized)
            var unknownVersion = try require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
            unknownVersion["version"] = 999
            let unknownData = try JSONSerialization.data(withJSONObject: unknownVersion)
            try expect(.invalidPayload) { _ = try WatchSyncPacket.decode(unknownData) }
            try expect(.invalidPayload) { _ = try WatchSyncPacket.decode(Data(repeating: 0, count: 60_001)) }
            var oversized = initialized
            oversized.bookmarks = [String(repeating: "x", count: 60_001)]
            try expect(.invalidPayload) { _ = try WatchSyncPacket.snapshot(oversized).encoded() }

            let operation = try require(replica.pending.first)
            let tooMany = WatchCounterBatch(deviceID: replica.deviceID,
                                           operations: Array(repeating: operation, count: WatchReplica.batchLimit + 1))
            try expect(.invalidPayload) { try tooMany.validate() }
            let overflow = WatchCounterBatch(deviceID: replica.deviceID, operations: [
                replacingSequence(operation, with: Int.max), replacingSequence(operation, with: 1)
            ])
            try expect(.invalidPayload) { try overflow.validate() }
            let noncontiguous = WatchCounterBatch(deviceID: replica.deviceID, operations: [
                replacingSequence(operation, with: 1), replacingSequence(operation, with: 3)
            ])
            try expect(.invalidPayload) { try noncontiguous.validate() }
            var exhausted = replica
            exhausted.lastSequence = Int.max
            try expect(.sequenceExhausted) { try exhausted.enqueue(.increment, now: date) }
            var full = replica
            full.pending = (1...WatchReplica.pendingLimit).map { replacingSequence(operation, with: $0) }
            full.lastSequence = WatchReplica.pendingLimit
            try expect(.queueFull) { try full.enqueue(.increment, now: date) }
            precondition(full.batch.operations.count == WatchReplica.batchLimit,
                         "A large offline outbox must be split into bounded transfer batches")
        }
    }

    private static func phoneRepository(at directory: URL, target: Int = 33) throws -> TasbihRepository {
        let repository = TasbihRepository(storage: TasbihFileStorage(directory: directory))
        _ = try repository.initializeApp(legacyData: nil)
        if target != 33 {
            _ = try repository.update { state in
                _ = state.setTarget(target, expectedID: state.selectedID, generation: state.progress.generation.uuidString, now: date)
            }
        }
        return repository
    }

    private static func deliver(_ batch: WatchCounterBatch, to repository: TasbihRepository) throws -> TasbihState {
        try batch.validate()
        var failure: (any Error)?
        let result = try repository.update { state in
            do { try batch.apply(to: &state) } catch { failure = error }
        }
        if let failure { throw failure }
        return try require(result)
    }

    private struct CounterSummary: Equatable {
        let count: Int
        let target: Int
        let generation: UUID
    }

    private static func counterSummaries(_ state: TasbihState) -> [String: CounterSummary] {
        state.counters.mapValues { CounterSummary(count: $0.count, target: $0.target, generation: $0.generation) }
    }

    private struct SessionSummary: Equatable {
        let dhikrID: String
        let count: Int
        let date: Date
    }

    private static func sessionSummaries(_ state: TasbihState) -> [SessionSummary] {
        state.sessions.map { SessionSummary(dhikrID: $0.dhikrID, count: $0.count, date: $0.date) }
    }

    private static func replacingSequence(_ operation: WatchCounterOperation, with sequence: Int) -> WatchCounterOperation {
        WatchCounterOperation(sequence: sequence, expectedID: operation.expectedID, generation: operation.generation,
                              replacementGeneration: operation.replacementGeneration, action: operation.action, date: operation.date)
    }

    private static func expect(_ expected: WatchSyncError, operation: () throws -> Void) throws {
        do {
            try operation()
            throw CheckError.expectedFailure
        } catch let actual as WatchSyncError {
            switch (expected, actual) {
            case (.invalidPayload, .invalidPayload), (.waitingForPhone, .waitingForPhone),
                 (.queueFull, .queueFull), (.sequenceExhausted, .sequenceExhausted): break
            default: throw CheckError.unexpectedFailure
            }
        }
    }

    private static func expectFailure(operation: () throws -> Void) throws {
        var failed = false
        do { try operation() } catch { failed = true }
        precondition(failed, "Expected a rejected storage commit")
    }

    private static func expectUnsupportedState(operation: () throws -> Void) throws {
        do {
            try operation()
            throw CheckError.expectedFailure
        } catch TasbihStorageError.unsupportedStateVersion { }
    }

    private static func require<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw CheckError.missingValue }
        return value
    }

    private static func withDirectory(_ name: String, operation: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rosery-watch-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(root)
    }

    private enum CheckError: Error { case missingValue, expectedFailure, unexpectedFailure, unexpectedPacket }
}
