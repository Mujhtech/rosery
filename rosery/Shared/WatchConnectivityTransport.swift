#if !ROSERY_WIDGET_EXTENSION && canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import Foundation
import WatchConnectivity

/// WCSession callbacks arrive on its serial delegate queue. Only Sendable packets cross to main.
@MainActor
final class WatchConnectivityTransport: NSObject, WCSessionDelegate {
    var onPacket: ((WatchSyncPacket) -> WatchSyncPacket?)?
    var onStatus: ((Bool, String?) -> Void)?
    private var session: WCSession?
    private var activationFailed = false
    private var activationRequested = false
    nonisolated private let delegateWork = WatchDelegateWork()
    private static let payloadKey = "rosery.counter.v1"

    var isReachable: Bool { session?.isReachable == true }

    func start() {
        guard WCSession.isSupported() else {
            onStatus?(false, "Watch connection is unavailable on this device.")
            return
        }
        if session == nil {
            session = WCSession.default
            session?.delegate = self
        }
        guard let session else { return }
        if session.activationState == .activated {
            activationFailed = false
            activationRequested = false
            becameReady()
        } else {
            // On iPhone a Watch switch must finish deactivation before reactivating.
            guard session.activationState != .inactive else { return }
            guard !activationRequested else { return }
            activationFailed = false
            activationRequested = true
            session.activate()
        }
    }

    /// SwiftUI owns the background task. Keep it alive until delivered packets have committed.
    /// Outgoing transfers and the durable outbox survive cancellation or the bounded deadline.
    func drainBackgroundDelivery() async {
        start()
        guard let session else { return }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        var settledSince: ContinuousClock.Instant?
        while !Task.isCancelled && clock.now < deadline {
            guard !activationFailed else { return }
            if session.activationState == .activated && !session.hasContentPending && delegateWork.pendingCount == 0 {
                if let settledSince, settledSince.duration(to: clock.now) >= .milliseconds(250) { return }
                if settledSince == nil { settledSince = clock.now }
            } else {
                settledSince = nil
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
        }
    }

    func sendRequest(_ packet: WatchSyncPacket) {
        guard let session, session.activationState == .activated else {
            start()
            return
        }
        do {
            let data = try packet.encoded()
            // Delivery survives suspension. An immediate reply may race this transfer; receipts
            // in the phone's counting transaction make both paths safe to deliver more than once.
            if !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo[Self.payloadKey] as? Data == data }) {
                session.transferUserInfo([Self.payloadKey: data])
            }
            if session.isReachable {
                session.sendMessageData(data, replyHandler: { [weak self] reply in
                    self?.enqueue { $0?.receive(reply) }
                }, errorHandler: { [weak self] _ in
                    self?.enqueue { $0?.onStatus?(false, "Waiting for iPhone. Your count is saved.") }
                })
            }
        } catch {
            onStatus?(isReachable, "Your count is saved. Try syncing again.")
        }
    }

    func publish(_ packet: WatchSyncPacket) {
        guard let session, session.activationState == .activated else {
            start()
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do {
            let data = try packet.encoded()
            try session.updateApplicationContext([Self.payloadKey: data])
            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
            }
        } catch {
            onStatus?(isReachable, "Your count is saved. Try syncing again.")
        }
    }

    private func becameReady() {
        if let data = session?.receivedApplicationContext[Self.payloadKey] as? Data { receive(data) }
        onStatus?(isReachable, nil)
    }

    private func receive(_ data: Data, reply: WatchDataReply? = nil) {
        do {
            let packet = try WatchSyncPacket.decode(data)
            let response = onPacket?(packet)
            reply?.call(try response?.encoded() ?? Data())
        } catch {
            reply?.call(Data())
            onStatus?(isReachable, "Couldn’t sync this update. Your saved count is unchanged.")
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        let failed = error != nil || activationState != .activated
        enqueue { transport in
            guard let transport else { return }
            transport.activationRequested = false
            transport.activationFailed = failed
            if failed { transport.onStatus?(false, "Open Rosery on iPhone to connect.") }
            else { transport.becameReady() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        enqueue { transport in
            guard let transport else { return }
            transport.onStatus?(transport.isReachable, nil)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["rosery.counter.v1"] as? Data else { return }
        enqueue { $0?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo["rosery.counter.v1"] as? Data else { return }
        enqueue { $0?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        enqueue { $0?.receive(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                             replyHandler: @escaping (Data) -> Void) {
        let reply = WatchDataReply(replyHandler)
        enqueue { transport in
            guard let transport else { reply.call(Data()); return }
            transport.receive(messageData, reply: reply)
        }
    }

    nonisolated private func enqueue(_ operation: @escaping @MainActor @Sendable (WatchConnectivityTransport?) -> Void) {
        let work = delegateWork
        work.begin()
        Task { @MainActor [weak self] in
            defer { work.finish() }
            operation(self)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        enqueue { transport in
            guard let transport else { return }
            transport.activationRequested = false
            transport.start()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        enqueue { $0?.becameReady() }
    }
    #endif
}

/// Incremented synchronously on the delegate queue, before its asynchronous main-actor hop.
nonisolated private final class WatchDelegateWork: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    func begin() {
        lock.lock()
        pending += 1
        lock.unlock()
    }

    func finish() {
        lock.lock()
        pending -= 1
        lock.unlock()
    }
}

/// WCSession owns this callback; invoking it on main is supported, and its lifetime spans the hop.
nonisolated private final class WatchDataReply: @unchecked Sendable {
    private let body: (Data) -> Void
    init(_ body: @escaping (Data) -> Void) { self.body = body }
    func call(_ data: Data) { body(data) }
}
#endif
