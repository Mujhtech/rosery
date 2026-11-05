//
//  roseryApp.swift
//  rosery
//
//  Created by Muhideen Mujeeb on 23/10/2026.
//

import SwiftUI
import Combine
import UIKit

@main
struct roseryApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: RoseryStore
    @State private var watchSync: PhoneWatchSync
    @State private var widgetRefresh = WidgetRefreshController()
    @State private var liveActivities = TasbihLiveActivityController()
    @State private var reminders: ReminderController

    init() {
        let store = RoseryStore()
        let watchSync = PhoneWatchSync(repository: store.watchSyncRepository)
        _store = State(initialValue: store)
        _watchSync = State(initialValue: watchSync)
        watchSync.start()
        let reminders = ReminderController()
        reminders.configure()
        _reminders = State(initialValue: reminders)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(liveActivities)
                .environment(reminders)
                .background {
                    WindowAppearance(appearance: store.preferences.appearance)
                        .frame(width: 0, height: 0)
                }
                .onAppear { [store, widgetRefresh, liveActivities, watchSync] in
                    store.onCounterChange = { [weak store, weak widgetRefresh, weak liveActivities, weak watchSync] in
                        widgetRefresh?.schedule()
                        watchSync?.schedule()
                        Task { @MainActor in
                            guard let store, let liveActivities else { return }
                            await liveActivities.refresh(snapshot: store.tasbihSnapshot)
                        }
                    }
                    store.refreshFromShared()
                    // Also replaces an "Open Rosery" entry after the first migration/launch.
                    widgetRefresh.schedule()
                    watchSync.schedule()
                }
                .task {
                    await reminders.refresh()
                    await liveActivities.refresh(snapshot: store.tasbihSnapshot)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshFromShared()
                        watchSync.schedule()
                        Task {
                            await reminders.refresh()
                            await liveActivities.refresh(snapshot: store.tasbihSnapshot)
                        }
                    }
                    if phase == .background {
                        widgetRefresh.flush()
                        watchSync.flush()
                        Task { await liveActivities.refresh(snapshot: store.tasbihSnapshot) }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .tasbihSharedCounterDidChange)) { _ in
                    store.refreshFromShared()
                    widgetRefresh.schedule()
                    watchSync.schedule()
                    Task { await liveActivities.refresh(snapshot: store.tasbihSnapshot) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
                    .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))) { _ in
                    Task { await reminders.refresh() }
                }
        }
    }
}
