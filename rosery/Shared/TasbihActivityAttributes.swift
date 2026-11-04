import Foundation
#if os(iOS)
import ActivityKit
#endif

/// One explicitly started counting round. A reset or target change creates a different round.
nonisolated struct TasbihActivityAttributes: Codable, Hashable, Sendable {
    let selectedID: String
    let generation: String
    let startedAt: Date

    enum Phase: String, Codable, Hashable, Sendable {
        case counting, complete, ended
    }

    struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var arabic: String
        var count: Int
        var target: Int
        var updatedAt: Date
        var phase: Phase

        var isComplete: Bool { phase == .complete }
        var staleDate: Date { updatedAt.addingTimeInterval(TasbihActivityPolicy.inactivityInterval) }

        func acceptsCount(at date: Date) -> Bool {
            phase == .counting && count >= 0 && count < target && date < staleDate
        }
    }

    func matches(_ snapshot: TasbihSnapshot) -> Bool {
        !snapshot.needsOpenApp && selectedID == snapshot.selectedID && generation == snapshot.generation
    }
}

#if os(iOS)
extension TasbihActivityAttributes: ActivityAttributes {}
#endif

/// Lifecycle decisions are shared with executable checks and contain no ActivityKit side effects.
nonisolated enum TasbihActivityPolicy {
    static let inactivityInterval: TimeInterval = 30 * 60
    static let maximumPayloadBytes = 4_096

    enum Decision: Equatable, Sendable {
        case unchanged
        case update(TasbihActivityAttributes.ContentState)
        case end(TasbihActivityAttributes.ContentState)
    }

    static func content(for snapshot: TasbihSnapshot, now: Date) -> TasbihActivityAttributes.ContentState {
        .init(title: snapshot.title, arabic: snapshot.arabic, count: snapshot.count, target: snapshot.target,
              updatedAt: now, phase: snapshot.isComplete ? .complete : .counting)
    }

    static func decision(attributes: TasbihActivityAttributes,
                         current: TasbihActivityAttributes.ContentState,
                         snapshot: TasbihSnapshot, now: Date, refreshStale: Bool) -> Decision {
        guard attributes.matches(snapshot) else { return .end(ended(current, now: now)) }
        let next = content(for: snapshot, now: now)
        if snapshot.isComplete { return .end(next) }
        // A terminal activity is never resumed by a later undo or ordinary refresh.
        guard current.phase == .counting else { return .end(ended(current, now: now)) }
        let changed = current.title != next.title || current.arabic != next.arabic
            || current.count != next.count || current.target != next.target
        if changed || (refreshStale && now >= current.staleDate) { return .update(next) }
        return .unchanged
    }

    static func ended(_ current: TasbihActivityAttributes.ContentState, now: Date) -> TasbihActivityAttributes.ContentState {
        var final = current
        final.phase = .ended
        final.updatedAt = now
        return final
    }

    static func fitsPayload(attributes: TasbihActivityAttributes,
                            content: TasbihActivityAttributes.ContentState) -> Bool {
        guard let attributesData = try? JSONEncoder().encode(attributes),
              let contentData = try? JSONEncoder().encode(content) else { return false }
        // Leave room under the limit even when the system includes both portions.
        return attributesData.count + contentData.count < maximumPayloadBytes
    }
}

nonisolated extension Notification.Name {
    static let tasbihSharedCounterDidChange = Notification.Name("rosery.tasbihSharedCounterDidChange")
}
