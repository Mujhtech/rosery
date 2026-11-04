import Foundation

@MainActor
final class PhoneWatchSync {
    private let repository: TasbihRepository
    private let transport = WatchConnectivityTransport()
    private var pending: Task<Void, Never>?
    // Owned for the app process lifetime, including intents that run without a visible scene.
    private var mutationObserver: (any NSObjectProtocol)?

    init(repository: TasbihRepository) {
        self.repository = repository
        transport.onPacket = { [weak self] packet in self?.receive(packet) }
        transport.onStatus = { [weak self] _, message in
            guard message == nil else { return }
            self?.publish()
        }
        mutationObserver = NotificationCenter.default.addObserver(forName: .tasbihSharedCounterDidChange,
                                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    func start() { transport.start() }

    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.publish()
        }
    }

    func flush() {
        pending?.cancel()
        pending = nil
        publish()
    }

    private func publish() {
        guard let state = try? repository.readState() else { return }
        transport.publish(.snapshot(state))
    }

    private func receive(_ packet: WatchSyncPacket) -> WatchSyncPacket? {
        guard case .request(let batch) = packet else { return nil }
        do {
            try batch.validate()
            var applyError: (any Error)?
            guard let state = try repository.update({ state in
                do { try batch.apply(to: &state) }
                catch { applyError = error }
            }), applyError == nil else { return nil }
            let snapshot = WatchSyncPacket.snapshot(state)
            transport.publish(snapshot)
            NotificationCenter.default.post(name: .tasbihSharedCounterDidChange, object: nil)
            return snapshot
        } catch {
            // Failed storage must never acknowledge an operation that was not committed.
            return nil
        }
    }
}
