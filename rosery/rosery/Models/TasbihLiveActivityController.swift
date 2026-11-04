import ActivityKit
import Observation
import UIKit

/// Live Activities are opt-in for one round. Restoring/refreshing never creates an activity.
@MainActor
@Observable
final class TasbihLiveActivityController {
    private(set) var isActive = false
    private(set) var isAvailable = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var activitiesTask: Task<Void, Never>?
    @ObservationIgnored private var stateTasks: [String: Task<Void, Never>] = [:]

    init() {
        reconcileActivities()
        authorizationTask = Task { @MainActor [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard !Task.isCancelled else { return }
                self?.isAvailable = enabled
                if !enabled {
                    _ = await TasbihActivityCoordinator.shared.stop()
                    self?.reconcileActivities()
                }
            }
        }
        activitiesTask = Task { @MainActor [weak self] in
            for await _ in Activity<TasbihActivityAttributes>.activityUpdates {
                guard !Task.isCancelled else { return }
                self?.reconcileActivities()
            }
        }
    }

    deinit {
        authorizationTask?.cancel()
        activitiesTask?.cancel()
        for task in stateTasks.values { task.cancel() }
    }

    func start(snapshot: TasbihSnapshot) async {
        errorMessage = nil
        let result = await TasbihActivityCoordinator.shared.start(snapshot: snapshot)
        errorMessage = result.errorMessage
        reconcileActivities()
    }

    func stop() async {
        errorMessage = nil
        let result = await TasbihActivityCoordinator.shared.stop()
        errorMessage = result.errorMessage
        reconcileActivities()
    }

    func refresh(snapshot: TasbihSnapshot) async {
        // The coordinator deliberately reloads persistence: a callback's snapshot may already
        // be superseded by an interactive widget tap. Only a foreground visit clears staleness.
        let result = await TasbihActivityCoordinator.shared.synchronize(
            refreshStale: UIApplication.shared.applicationState == .active && !snapshot.needsOpenApp)
        errorMessage = result.errorMessage
        reconcileActivities()
    }

    private func reconcileActivities() {
        isAvailable = ActivityAuthorizationInfo().areActivitiesEnabled
        let activities = Activity<TasbihActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
        let ids = Set(activities.map(\.id))
        isActive = !activities.isEmpty
        for id in stateTasks.keys where !ids.contains(id) {
            stateTasks.removeValue(forKey: id)?.cancel()
        }
        for activity in activities where stateTasks[activity.id] == nil {
            stateTasks[activity.id] = Task { @MainActor [weak self] in
                for await _ in activity.activityStateUpdates {
                    guard !Task.isCancelled else { return }
                    self?.reconcileActivities()
                }
            }
        }
    }
}
