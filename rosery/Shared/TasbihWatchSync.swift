import Foundation

/// Only operations travel from Watch to iPhone. A cached Watch snapshot never replaces phone state.
nonisolated enum WatchCounterAction: Codable, Equatable, Sendable {
    case increment, undo, next
    case select(String)
    case target(Int)
    case restart(Int?)
}

nonisolated struct WatchCounterOperation: Codable, Equatable, Sendable {
    let sequence: Int
    let expectedID: String
    let generation: UUID
    let replacementGeneration: UUID
    let action: WatchCounterAction
    let date: Date

    @discardableResult
    func apply(to state: inout TasbihState) -> Bool {
        guard state.matches(expectedID, generation: generation.uuidString) else { return false }
        switch action {
        case .increment:
            state.increment(expectedID: expectedID, generation: generation.uuidString, now: date)
        case .undo:
            state.undo(expectedID: expectedID, generation: generation.uuidString)
        case .select(let id):
            guard let dhikr = DhikrLibrary.reading(id: id), dhikr.isCounterPhrase else { return false }
            let changesSelection = state.selectedID != id
            state.select(dhikr)
            if changesSelection { state.counters[id]?.generation = replacementGeneration }
        case .target(let target):
            guard (1...10_000).contains(target), target >= state.progress.count else { return false }
            let changesTarget = target != state.progress.target
            guard state.setTarget(target, expectedID: expectedID, generation: generation.uuidString, now: date) else { return false }
            if changesTarget { state.counters[state.selectedID]?.generation = replacementGeneration }
        case .restart(let target):
            guard target.map({ (1...10_000).contains($0) }) ?? true else { return false }
            guard state.resetCounter(target: target, expectedID: expectedID, generation: generation.uuidString) else { return false }
            state.counters[state.selectedID]?.generation = replacementGeneration
        case .next:
            guard state.nextAfterPrayer != nil else { return false }
            state.beginNextAfterPrayer(expectedID: expectedID, generation: generation.uuidString)
            state.counters[state.selectedID]?.generation = replacementGeneration
        }
        return true
    }
}

nonisolated struct WatchCounterBatch: Codable, Equatable, Sendable {
    let deviceID: UUID
    let operations: [WatchCounterOperation]

    func validate() throws {
        guard operations.count <= WatchReplica.batchLimit else { throw WatchSyncError.invalidPayload }
        var previous: Int?
        for operation in operations {
            guard operation.sequence > 0,
                  operation.date.timeIntervalSince1970.isFinite,
                  DhikrLibrary.reading(id: operation.expectedID)?.isCounterPhrase == true else {
                throw WatchSyncError.invalidPayload
            }
            if let previous {
                guard previous < Int.max, operation.sequence == previous + 1 else { throw WatchSyncError.invalidPayload }
            }
            previous = operation.sequence
        }
    }

    /// Runs inside the same file transaction as phone/widget mutations, including its receipt.
    func apply(to state: inout TasbihState) throws {
        try validate()
        let key = deviceID.uuidString
        var acknowledged = state.watchSequences[key, default: 0]
        for operation in operations where operation.sequence > acknowledged {
            guard operation.sequence == acknowledged + 1 else { break }
            if !operation.apply(to: &state) {
                var rejected = state.watchRejections[key, default: []]
                rejected.append(operation.sequence)
                state.watchRejections[key] = Array(rejected.suffix(32))
            }
            acknowledged = operation.sequence
        }
        if acknowledged > state.watchSequences[key, default: 0] {
            state.watchSequences[key] = acknowledged
        }
    }
}

nonisolated enum WatchSyncPacket: Codable, Sendable {
    case request(WatchCounterBatch)
    case snapshot(TasbihState)

    private struct Envelope: Codable {
        let version: Int
        let packet: WatchSyncPacket
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: 1, packet: self))
        guard data.count <= 60_000 else { throw WatchSyncError.invalidPayload }
        return data
    }

    static func decode(_ data: Data) throws -> WatchSyncPacket {
        guard data.count <= 60_000 else { throw WatchSyncError.invalidPayload }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else { throw WatchSyncError.invalidPayload }
        if case .request(let batch) = envelope.packet { try batch.validate() }
        return envelope.packet
    }
}

nonisolated enum WatchSyncError: Error {
    case invalidPayload, waitingForPhone, queueFull, sequenceExhausted
}

/// Durable confirmed state and an ordered outbox. Projection makes offline interactions immediate.
nonisolated struct WatchReplica: Codable, Equatable, Sendable {
    static let batchLimit = 64
    static let pendingLimit = 20_000
    var deviceID = UUID()
    var lastSequence = 0
    var confirmed: TasbihState?
    var pending: [WatchCounterOperation] = []
    var lastNoticedRejection = 0
    var hasConflictNotice = false
    var retiredPhoneEpochs: [UUID] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case deviceID, lastSequence, confirmed, pending, lastNoticedRejection, hasConflictNotice, retiredPhoneEpochs
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try values.decode(UUID.self, forKey: .deviceID)
        lastSequence = try values.decode(Int.self, forKey: .lastSequence)
        confirmed = try values.decodeIfPresent(TasbihState.self, forKey: .confirmed)
        pending = try values.decode([WatchCounterOperation].self, forKey: .pending)
        lastNoticedRejection = try values.decodeIfPresent(Int.self, forKey: .lastNoticedRejection) ?? 0
        hasConflictNotice = try values.decodeIfPresent(Bool.self, forKey: .hasConflictNotice) ?? false
        retiredPhoneEpochs = try values.decodeIfPresent([UUID].self, forKey: .retiredPhoneEpochs) ?? []
        guard lastSequence >= 0, pending.count <= Self.pendingLimit,
              pending.last.map({ $0.sequence <= lastSequence }) ?? true,
              confirmed != nil || pending.isEmpty else { throw WatchSyncError.invalidPayload }
        for (index, operation) in pending.enumerated() {
            guard operation.sequence > 0 else { throw WatchSyncError.invalidPayload }
            if index > 0 {
                let previous = pending[index - 1].sequence
                guard previous < Int.max, operation.sequence == previous + 1 else { throw WatchSyncError.invalidPayload }
            }
        }
    }

    var projected: TasbihState? {
        guard var state = confirmed else { return nil }
        for operation in pending { operation.apply(to: &state) }
        return state
    }

    var batch: WatchCounterBatch {
        WatchCounterBatch(deviceID: deviceID, operations: Array(pending.prefix(Self.batchLimit)))
    }

    mutating func enqueue(_ action: WatchCounterAction, now: Date = .now) throws {
        guard let state = projected else { throw WatchSyncError.waitingForPhone }
        guard pending.count < Self.pendingLimit else { throw WatchSyncError.queueFull }
        guard lastSequence < Int.max else { throw WatchSyncError.sequenceExhausted }
        let operation = WatchCounterOperation(sequence: lastSequence + 1, expectedID: state.selectedID,
                                              generation: state.progress.generation,
                                              replacementGeneration: UUID(), action: action, date: now)
        var next = state
        guard operation.apply(to: &next) else { throw WatchSyncError.invalidPayload }
        // Don't enqueue inert taps on a completed round or Undo at zero.
        guard next != state else { return }
        lastSequence += 1
        pending.append(operation)
        hasConflictNotice = false
    }

    @discardableResult
    mutating func receive(_ state: TasbihState) -> Bool {
        guard !retiredPhoneEpochs.contains(state.syncEpoch) else { return false }
        if let confirmed, confirmed.syncEpoch != state.syncEpoch {
            retiredPhoneEpochs.append(confirmed.syncEpoch)
            // A fresh phone installation has a new receipt ledger and different counting rounds.
            // Never replay operations created for the previous installation into it.
            hasConflictNotice = !pending.isEmpty
            pending.removeAll()
            deviceID = UUID()
            lastSequence = 0
            lastNoticedRejection = 0
            self.confirmed = state
            return true
        }
        guard confirmed.map({ state.syncRevision >= $0.syncRevision }) ?? true else { return false }
        let acknowledged = state.watchSequences[deviceID.uuidString, default: 0]
        // A receipt cannot acknowledge operations that this installation never issued.
        guard acknowledged <= lastSequence else { return false }
        if let rejection = state.watchRejections[deviceID.uuidString]?.max(), rejection > lastNoticedRejection {
            lastNoticedRejection = rejection
            hasConflictNotice = true
        }
        confirmed = state
        pending.removeAll { $0.sequence <= acknowledged }
        return true
    }
}

nonisolated final class WatchReplicaRepository: Sendable {
    private let storage: any TasbihStorage
    init(storage: any TasbihStorage) { self.storage = storage }

    static func local() -> WatchReplicaRepository {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TasbihShared.appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return WatchReplicaRepository(storage: TasbihFileStorage(directory: root.appendingPathComponent("WatchCounter", isDirectory: true)))
    }

    func load() throws -> WatchReplica {
        try storage.withData { data in
            if let data { return try JSONDecoder().decode(WatchReplica.self, from: data) }
            let replica = WatchReplica()
            data = try JSONEncoder().encode(replica)
            return replica
        }
    }

    @discardableResult
    func update(_ operation: (inout WatchReplica) throws -> Void) throws -> WatchReplica {
        try storage.withData { data in
            var replica = try data.map { try JSONDecoder().decode(WatchReplica.self, from: $0) } ?? WatchReplica()
            try operation(&replica)
            data = try JSONEncoder().encode(replica)
            return replica
        }
    }
}
