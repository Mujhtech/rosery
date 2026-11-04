import SwiftUI

@main
struct RoseryWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: WatchStore

    init() {
        let store = WatchStore()
        _store = State(initialValue: store)
        store.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchCounterView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(WatchRoseryTheme.accent)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.refresh()
                }
        }
        .backgroundTask(.watchConnectivity) { [store] in
            await store.handleBackgroundConnectivity()
        }
    }
}
