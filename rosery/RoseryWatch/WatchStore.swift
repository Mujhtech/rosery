import Foundation
import Observation

@MainActor
@Observable
final class WatchStore {
    private(set) var state: TasbihState?
    private(set) var isConnected = false
    private(set) var pendingCount = 0
    private(set) var persistenceError: String?
    private(set) var hasConflictNotice = false
    @ObservationIgnored private let repository: WatchReplicaRepository
    @ObservationIgnored private let transport = WatchConnectivityTransport()
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var backgroundDeliveryCount = 0
    @ObservationIgnored private var fallback: TasbihState

    init(repository: WatchReplicaRepository = .local()) {
        self.repository = repository
        var fallback = TasbihState()
        fallback.normalize()
        self.fallback = fallback
        do {
            #if DEBUG
            if ProcessInfo.processInfo.environment["ROSERY_WATCH_PREVIEW"] == "1" {
                fallback.counters[fallback.selectedID]?.count = 12
                apply(try repository.update { replica in
                    if replica.confirmed == nil { replica.confirmed = fallback }
                })
            } else {
                apply(try repository.load())
            }
            #else
            apply(try repository.load())
            #endif
        } catch {
            persistenceError = "Couldn’t read your saved count. Try again."
        }
    }

    var selectedDhikr: Dhikr { (state ?? fallback).selectedDhikr }
    var progress: CounterProgress { (state ?? fallback).progress }
    var preferences: ReadingPreferences { (state ?? fallback).preferences }
    var nextAfterPrayer: Dhikr? { state?.nextAfterPrayer }
    var isReady: Bool { state != nil }
    var statusMessage: String {
        if let persistenceError { return persistenceError }
        if hasConflictNotice { return "The round changed on iPhone. Earlier pending changes weren’t added." }
        if !isReady { return "Open Rosery on iPhone to connect." }
        if pendingCount > 0 { return "\(pendingCount) \(pendingCount == 1 ? "change" : "changes") waiting to sync" }
        return isConnected ? "Synced with iPhone" : "Saved on Watch"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        transport.onPacket = { [weak self] packet in
            guard case .snapshot(let state) = packet, let self else { return nil }
            do {
                let previousPending = self.pendingCount
                let replica = try self.repository.update { _ = $0.receive(state) }
                self.apply(replica)
                self.persistenceError = nil
                if self.pendingCount < previousPending || self.pendingCount == 0 { self.retryAttempt = 0 }
                if !replica.pending.isEmpty {
                    if self.backgroundDeliveryCount > 0 { self.requestSync() }
                    else { self.scheduleSync() }
                }
            } catch {
                self.persistenceError = "Couldn’t save this update. Your earlier count is safe."
            }
            return nil
        }
        transport.onStatus = { [weak self] reachable, message in
            guard let self else { return }
            self.isConnected = reachable
            if let message, self.persistenceError == nil, !self.isReady { self.persistenceError = message }
            guard message == nil else {
                if self.pendingCount > 0 { self.scheduleRetry() }
                return
            }
            self.retryAttempt = 0
            self.requestSync()
        }
        transport.start()
        requestSync()
    }

    func handleBackgroundConnectivity() async {
        backgroundDeliveryCount += 1
        defer { backgroundDeliveryCount -= 1 }
        start()
        pendingSync?.cancel()
        pendingSync = nil
        requestSync()
        await transport.drainBackgroundDelivery()
    }

    func refresh() {
        do {
            apply(try repository.load())
            persistenceError = nil
        } catch {
            persistenceError = "Couldn’t read your saved count. Try again."
        }
        requestSync()
    }

    func requestSync() {
        do {
            let replica = try repository.load()
            transport.sendRequest(.request(replica.batch))
        } catch {
            persistenceError = "Couldn’t read your saved count. Try again."
        }
    }

    private func scheduleRetry() {
        guard retryAttempt < 3 else { return }
        let delay = [3, 15, 45][retryAttempt]
        retryAttempt += 1
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingSync = nil
            self.requestSync()
        }
    }

    func increment() { change(.increment) }
    func undo() { change(.undo) }
    func select(_ dhikr: Dhikr) { change(.select(dhikr.id)) }
    func restart(target: Int? = nil) { change(.restart(target)) }
    func beginNextAfterPrayer() { change(.next) }

    @discardableResult
    func setTarget(_ target: Int) -> Bool {
        guard (1...10_000).contains(target), target >= progress.count else { return false }
        return change(.target(target))
    }

    @discardableResult
    private func change(_ action: WatchCounterAction) -> Bool {
        do {
            apply(try repository.update { try $0.enqueue(action) })
            persistenceError = nil
            scheduleSync()
            return true
        } catch WatchSyncError.waitingForPhone {
            persistenceError = "Open Rosery on iPhone to connect first."
        } catch WatchSyncError.queueFull {
            persistenceError = "Connect to iPhone before adding more counts. Your progress is saved."
        } catch {
            persistenceError = "Couldn’t save this count. Please try again."
        }
        return false
    }

    private func apply(_ replica: WatchReplica) {
        state = replica.projected
        pendingCount = replica.pending.count
        hasConflictNotice = replica.hasConflictNotice
    }

    private func scheduleSync() {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingSync = nil
            self.requestSync()
        }
    }
}
