import Foundation

nonisolated enum TasbihActivityCounterAction: Sendable { case increment, undo }

/// Uses the repository's transaction and the existing domain operations; no counting logic is copied.
nonisolated enum TasbihActivityMutation {
    struct Result: Sendable {
        let snapshot: TasbihSnapshot
        let changed: Bool
    }

    static func apply(_ action: TasbihActivityCounterAction, repository: TasbihRepository,
                      expectedID: String, generation: String, requiresIncompleteRound: Bool = false,
                      now: Date = .now) throws -> Result {
        var changed = false
        let state = try repository.update { state in
            guard state.matches(expectedID, generation: generation) else { return }
            // The app may finish between the visible Activity guard and this transaction.
            // A delayed Live Activity Undo must not reopen that completed round.
            guard !requiresIncompleteRound || !state.progress.isComplete else { return }
            let previous = state.progress.count
            switch action {
            case .increment: state.increment(expectedID: expectedID, generation: generation, now: now)
            case .undo: state.undo(expectedID: expectedID, generation: generation)
            }
            changed = previous != state.progress.count
        }
        return Result(snapshot: TasbihSnapshot(state: state), changed: changed)
    }
}

#if os(iOS)
@preconcurrency import ActivityKit
import WidgetKit

/// All intents run in the app process. This mailbox serializes ActivityKit calls across awaits,
/// coalesces pending refreshes, and reads storage at publication time instead of queuing counts.
@MainActor
final class TasbihActivityCoordinator {
    static let shared = TasbihActivityCoordinator()

    struct Outcome: Sendable {
        let isActive: Bool
        var errorMessage: String?
    }

    private enum Command {
        case synchronize(refreshStale: Bool)
        case start(expected: TasbihSnapshot)
        case stop(expectedID: String?, generation: String?)
        case change(TasbihActivityCounterAction, expectedID: String, generation: String, requiresActivity: Bool)
    }

    private struct Pending {
        var command: Command
        var waiters: [CheckedContinuation<Outcome, Never>]
    }

    private var pending: [Pending] = []
    private var isDraining = false
    private var lastPublication = Date.distantPast

    func synchronize(refreshStale: Bool = false) async -> Outcome {
        await submit(.synchronize(refreshStale: refreshStale))
    }

    func start(snapshot: TasbihSnapshot) async -> Outcome {
        await submit(.start(expected: snapshot))
    }

    func stop(expectedID: String? = nil, generation: String? = nil) async -> Outcome {
        await submit(.stop(expectedID: expectedID, generation: generation))
    }

    func change(_ action: TasbihActivityCounterAction, expectedID: String, generation: String,
                requiresActivity: Bool) async -> Outcome {
        await submit(.change(action, expectedID: expectedID, generation: generation, requiresActivity: requiresActivity))
    }

    private func submit(_ command: Command) async -> Outcome {
        await withCheckedContinuation { continuation in
            if case .synchronize(let refresh) = command,
               let index = pending.lastIndex(where: { if case .synchronize = $0.command { true } else { false } }),
               case .synchronize(let earlierRefresh) = pending[index].command {
                pending[index].command = .synchronize(refreshStale: earlierRefresh || refresh)
                pending[index].waiters.append(continuation)
            } else {
                pending.append(Pending(command: command, waiters: [continuation]))
            }
            guard !isDraining else { return }
            isDraining = true
            Task { await drain() }
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let next = pending.removeFirst()
            let outcome = await perform(next.command)
            for waiter in next.waiters { waiter.resume(returning: outcome) }
        }
        isDraining = false
    }

    private func perform(_ command: Command) async -> Outcome {
        switch command {
        case .synchronize(let refreshStale):
            return await synchronizeLatest(refreshStale: refreshStale)
        case .start(let expected):
            return await startCurrent(expected: expected)
        case .stop(let expectedID, let generation):
            for activity in ongoingActivities {
                if let expectedID, let generation,
                   (activity.attributes.selectedID != expectedID || activity.attributes.generation != generation) { continue }
                await end(activity, state: TasbihActivityPolicy.ended(activity.content.state, now: .now))
            }
            return outcome()
        case .change(let action, let expectedID, let generation, let requiresActivity):
            return await changeCurrent(action, expectedID: expectedID, generation: generation,
                                       requiresActivity: requiresActivity)
        }
    }

    private var ongoingActivities: [Activity<TasbihActivityAttributes>] {
        Activity<TasbihActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private func outcome(error: String? = nil) -> Outcome {
        Outcome(isActive: !ongoingActivities.isEmpty, errorMessage: error)
    }

    private func latestSnapshot() async throws -> TasbihSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try TasbihRepository.appGroup().snapshot()
        }.value
    }

    private func synchronizeLatest(refreshStale: Bool) async -> Outcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return outcome()
        }
        do {
            let snapshot = try await latestSnapshot()
            guard !snapshot.needsOpenApp else { throw TasbihStorageError.notInitialized }
            return await publish(snapshot, refreshStale: refreshStale)
        } catch {
            await endAll()
            return outcome(error: "Rosery couldn’t read your saved count. Open the app and try again.")
        }
    }

    private func publish(_ snapshot: TasbihSnapshot, refreshStale: Bool) async -> Outcome {
        var keptCurrentRound = false
        for activity in ongoingActivities.sorted(by: { $0.attributes.startedAt > $1.attributes.startedAt }) {
            // Restore at most one activity if an earlier app run left duplicate activities behind.
            if keptCurrentRound, activity.attributes.matches(snapshot) {
                await end(activity, state: TasbihActivityPolicy.ended(activity.content.state, now: .now))
                continue
            }
            let decision = TasbihActivityPolicy.decision(attributes: activity.attributes, current: activity.content.state,
                                                        snapshot: snapshot, now: .now, refreshStale: refreshStale)
            switch decision {
            case .unchanged:
                keptCurrentRound = true
            case .update(let state):
                guard TasbihActivityPolicy.fitsPayload(attributes: activity.attributes, content: state) else {
                    await endAll()
                    return outcome(error: "This remembrance couldn’t be shown in a Live Activity.")
                }
                await update(activity, state: state)
                keptCurrentRound = true
            case .end(let state):
                await end(activity, state: state)
            }
        }
        return outcome()
    }

    private func startCurrent(expected: TasbihSnapshot) async -> Outcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return outcome(error: "Live Activities are turned off for Rosery in Settings.")
        }
        do {
            let snapshot = try await latestSnapshot()
            guard !snapshot.needsOpenApp else { throw TasbihStorageError.notInitialized }
            guard !expected.needsOpenApp, snapshot.selectedID == expected.selectedID,
                  snapshot.generation == expected.generation else {
                _ = await publish(snapshot, refreshStale: false)
                return outcome(error: "This round changed. Try starting the Live Activity again.")
            }
            guard !snapshot.isComplete else {
                _ = await publish(snapshot, refreshStale: false)
                return outcome(error: "Start a new round before showing it on your Lock Screen.")
            }
            _ = await publish(snapshot, refreshStale: true)
            if ongoingActivities.contains(where: { $0.attributes.matches(snapshot) }) { return outcome() }
            let now = Date.now
            let attributes = TasbihActivityAttributes(selectedID: snapshot.selectedID,
                                                      generation: snapshot.generation, startedAt: now)
            let state = TasbihActivityPolicy.content(for: snapshot, now: now)
            guard TasbihActivityPolicy.fitsPayload(attributes: attributes, content: state) else {
                return outcome(error: "This remembrance couldn’t be shown in a Live Activity.")
            }
            _ = try Activity.request(attributes: attributes,
                                     content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
            // A reset/selection can occur while ActivityKit requests the presentation.
            return await synchronizeLatest(refreshStale: false)
        } catch {
            await endAll()
            return outcome(error: "The Live Activity couldn’t start. Open Rosery and try again.")
        }
    }

    private func changeCurrent(_ action: TasbihActivityCounterAction, expectedID: String, generation: String,
                               requiresActivity: Bool) async -> Outcome {
        guard !expectedID.isEmpty, !generation.isEmpty else { return await synchronizeLatest(refreshStale: false) }
        if requiresActivity {
            let valid = ActivityAuthorizationInfo().areActivitiesEnabled && ongoingActivities.contains { activity in
                activity.attributes.selectedID == expectedID && activity.attributes.generation == generation
                    && activity.activityState == .active && activity.content.state.acceptsCount(at: .now)
            }
            guard valid else { return await synchronizeLatest(refreshStale: false) }
        }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try TasbihActivityMutation.apply(action, repository: TasbihRepository.appGroup(),
                                                 expectedID: expectedID, generation: generation,
                                                 requiresIncompleteRound: requiresActivity)
            }.value
            guard !result.snapshot.needsOpenApp else { throw TasbihStorageError.notInitialized }
            // Read again at publication: another app-side mutation may have committed during the await.
            let synchronized = await synchronizeLatest(refreshStale: false)
            if result.changed {
                WidgetCenter.shared.reloadTimelines(ofKind: TasbihShared.widgetKind)
                NotificationCenter.default.post(name: .tasbihSharedCounterDidChange, object: nil)
            }
            return synchronized
        } catch {
            await endAll()
            return outcome(error: "Rosery couldn’t save your count. Open the app and try again.")
        }
    }

    private func timestamp(after stateDate: Date) -> Date {
        let value = max(.now, max(lastPublication, stateDate).addingTimeInterval(0.001))
        lastPublication = value
        return value
    }

    private func update(_ activity: Activity<TasbihActivityAttributes>, state: TasbihActivityAttributes.ContentState) async {
        let content = ActivityContent(state: state, staleDate: state.staleDate)
        if #available(iOS 17.2, *) {
            await activity.update(content, timestamp: timestamp(after: activity.content.state.updatedAt))
        } else {
            await activity.update(content)
        }
    }

    private func end(_ activity: Activity<TasbihActivityAttributes>, state: TasbihActivityAttributes.ContentState) async {
        let content = ActivityContent(state: state, staleDate: nil)
        if #available(iOS 17.2, *) {
            await activity.end(content, dismissalPolicy: .immediate,
                               timestamp: timestamp(after: activity.content.state.updatedAt))
        } else {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private func endAll() async {
        for activity in ongoingActivities {
            await end(activity, state: TasbihActivityPolicy.ended(activity.content.state, now: .now))
        }
    }
}
#endif
