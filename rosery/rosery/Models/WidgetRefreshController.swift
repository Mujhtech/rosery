import WidgetKit

/// Coalesces rapid app taps; the final count is published before the app is suspended.
@MainActor
final class WidgetRefreshController {
    private var pending: Task<Void, Never>?

    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            WidgetCenter.shared.reloadTimelines(ofKind: TasbihShared.widgetKind)
        }
    }

    func flush() {
        guard pending != nil else { return }
        pending?.cancel()
        pending = nil
        WidgetCenter.shared.reloadTimelines(ofKind: TasbihShared.widgetKind)
    }
}
