import Foundation
import UserNotifications

/// All controller tests use memory and a fake adapter, never the notification service.
nonisolated final class ReminderMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

@MainActor
private final class ReminderTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var entered = false

    func suspend() async {
        await withCheckedContinuation {
            continuation = $0
            entered = true
            observers.forEach { $0.resume() }
            observers.removeAll()
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class FakeReminderNotifications: ReminderNotificationAdapter {
    var authorization = ReminderAuthorization.notDetermined
    var authorizationAfterRequest = ReminderAuthorization.authorized
    var rejectPermission = false
    var rejectSchedule = false
    var nextAddGate: ReminderTestGate?
    var pending: [String: ReminderPreferences] = ["unrelated.pending": .standard]
    var delivered: Set<String> = ["unrelated.delivered"]
    var installCount = 0
    var authorizationReads = 0
    var permissionRequests = 0
    var added: [ReminderPreferences] = []
    var removedPending: [[String]] = []
    var removedDelivered: [[String]] = []
    private var tapHandler: (@MainActor @Sendable () -> Void)?

    func installTapHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        installCount += 1
        tapHandler = handler
    }

    func authorizationStatus() async -> ReminderAuthorization {
        authorizationReads += 1
        return authorization
    }

    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if rejectPermission { throw TestError.rejected }
        authorization = authorizationAfterRequest
        return authorization == .authorized
    }

    func addDailyReminder(_ preferences: ReminderPreferences) async throws {
        if let gate = nextAddGate {
            nextAddGate = nil
            await gate.suspend()
        }
        if rejectSchedule { throw TestError.rejected }
        added.append(preferences)
        pending[ReminderPreferences.notificationIdentifier] = preferences
    }

    func removePending(identifiers: [String]) {
        removedPending.append(identifiers)
        identifiers.forEach { pending[$0] = nil }
    }

    func removeDelivered(identifiers: [String]) {
        removedDelivered.append(identifiers)
        identifiers.forEach { delivered.remove($0) }
    }

    func tap() { tapHandler?() }

    private enum TestError: Error { case rejected }
}

@main
struct ReminderChecks {
    @MainActor
    static func main() async throws {
        try checkPreferencesAndRequest()
        try await checkOptInAndPersistence()
        try await checkPermissionChanges()
        try await checkFailuresAndRecovery()
        try await checkSerializedChanges()
        await checkTapRouting()
        print("PASS: reminder defaults and validation; local repeating request; opt-in-only permission; persisted time; denied/revoked/provisional permission; owned-only cancellation; scheduling and permission failures; serialized time/disable changes; notification tap routing. No system notifications were requested or scheduled.")
    }

    @MainActor
    private static func checkPreferencesAndRequest() throws {
        assert(ReminderPreferences.standard == ReminderPreferences())
        assert(!ReminderPreferences.standard.isEnabled)
        assert(ReminderPreferences.standard.hour == 8 && ReminderPreferences.standard.minute == 0)
        for text in ["{}", "{\"isEnabled\":null,\"hour\":null,\"minute\":null}"] {
            let decoded = try JSONDecoder().decode(ReminderPreferences.self, from: Data(text.utf8))
            assert(decoded == .standard)
        }
        for pair in [(0, 0), (8, 0), (22, 17), (23, 59)] {
            let preferences = try ReminderPreferences(isEnabled: true, hour: pair.0, minute: pair.1)
            let decoded = try JSONDecoder().decode(ReminderPreferences.self, from: JSONEncoder().encode(preferences))
            assert(decoded == preferences)
        }
        for pair in [(-1, 0), (24, 0), (8, -1), (8, 60)] {
            do {
                _ = try ReminderPreferences(isEnabled: false, hour: pair.0, minute: pair.1)
                assertionFailure("Out-of-range time must be rejected")
            } catch ReminderPreferences.ValidationError.invalidTime { }
        }
        for text in ["{\"hour\":24}", "{\"minute\":-1}", "{\"hour\":\"8\"}", "[]"] {
            assert((try? JSONDecoder().decode(ReminderPreferences.self, from: Data(text.utf8))) == nil)
        }

        let preferences = try ReminderPreferences(isEnabled: true, hour: 22, minute: 17)
        let request = SystemReminderNotificationAdapter.request(for: preferences)
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        assert(request.identifier == ReminderPreferences.notificationIdentifier)
        assert(request.content.title == "A moment of remembrance")
        assert(!request.content.body.isEmpty && request.content.sound != nil)
        assert(request.content.userInfo["route"] as? String == "tasbih")
        assert(trigger?.repeats == true)
        assert(trigger?.dateComponents.hour == 22 && trigger?.dateComponents.minute == 17)
        assert(trigger?.dateComponents.timeZone == nil && trigger?.dateComponents.calendar == nil)
        assert(trigger?.dateComponents.year == nil && trigger?.dateComponents.day == nil)
    }

    @MainActor
    private static func checkOptInAndPersistence() async throws {
        let defaults = ReminderMemoryDefaults()
        let sentinel = Data("unrelated reading and tasbih state".utf8)
        defaults.set(sentinel, forKey: "unrelated.saved.state")
        let adapter = FakeReminderNotifications()
        let controller = ReminderController(defaults: defaults, notifications: adapter)
        assert(controller.status == .disabled && controller.preferences == .standard)
        assert(adapter.installCount == 0 && adapter.permissionRequests == 0 && adapter.added.isEmpty)
        controller.configure()
        controller.configure()
        assert(adapter.installCount == 1)
        await controller.refresh()
        await controller.setTime(localTime(hour: 21, minute: 45))
        assert(adapter.permissionRequests == 0 && adapter.authorizationReads == 0 && adapter.added.isEmpty)
        assert(controller.preferences.hour == 21 && controller.preferences.minute == 45)
        assert(controller.status == .disabled && !controller.needsSettings)

        await controller.setEnabled(true)
        assert(adapter.permissionRequests == 1 && adapter.authorizationReads == 2)
        assert(controller.preferences.isEnabled && controller.status == .scheduled)
        assert(controller.errorMessage == nil && !controller.isUpdating)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == controller.preferences)
        assert(adapter.pending.count == 2, "The daily reminder must share one stable identifier")
        await controller.refresh()
        await controller.setTime(localTime(hour: 6, minute: 5))
        assert(adapter.permissionRequests == 1 && adapter.pending.count == 2)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier]?.hour == 6)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier]?.minute == 5)
        assert(defaults.data(forKey: "unrelated.saved.state") == sentinel)

        let restored = ReminderController(defaults: defaults, notifications: adapter)
        assert(restored.preferences == controller.preferences)
        await restored.refresh()
        assert(restored.status == .scheduled && adapter.permissionRequests == 1)
        adapter.delivered.insert(ReminderPreferences.notificationIdentifier)
        await restored.setEnabled(false)
        assert(restored.status == .disabled && !restored.preferences.isEnabled)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == nil)
        assert(!adapter.delivered.contains(ReminderPreferences.notificationIdentifier))
        assert(adapter.pending["unrelated.pending"] != nil && adapter.delivered.contains("unrelated.delivered"))
        assert(adapter.removedPending.allSatisfy { $0 == [ReminderPreferences.notificationIdentifier] })
        assert(adapter.removedDelivered.allSatisfy { $0 == [ReminderPreferences.notificationIdentifier] })
        assert(ReminderController(defaults: defaults, notifications: adapter).preferences == restored.preferences)
    }

    @MainActor
    private static func checkPermissionChanges() async throws {
        let defaults = ReminderMemoryDefaults()
        defaults.set(try JSONEncoder().encode(ReminderPreferences(isEnabled: true, hour: 8, minute: 30)),
                     forKey: ReminderPreferences.storageKey)
        let adapter = FakeReminderNotifications()
        let controller = ReminderController(defaults: defaults, notifications: adapter)
        await controller.refresh()
        assert(controller.status == .needsPermission && adapter.permissionRequests == 0)
        await controller.setTime(localTime(hour: 9, minute: 10))
        assert(controller.status == .needsPermission && adapter.permissionRequests == 0)
        adapter.authorizationAfterRequest = .denied
        await controller.setEnabled(true)
        assert(controller.status == .blocked && controller.needsSettings)
        assert(adapter.permissionRequests == 1 && adapter.added.isEmpty)
        await controller.refresh()
        await controller.setEnabled(true)
        assert(adapter.permissionRequests == 1, "Denied authorization must lead to Settings, not another prompt")

        adapter.authorization = .authorized
        await controller.refresh()
        assert(controller.status == .scheduled && !controller.needsSettings)
        adapter.authorization = .denied
        await controller.refresh()
        assert(controller.status == .blocked && adapter.pending[ReminderPreferences.notificationIdentifier] == nil)
        adapter.authorization = .provisional
        await controller.refresh()
        assert(controller.status == .scheduledQuietly && controller.summary.contains("quietly"))
        adapter.authorization = .ephemeral
        await controller.refresh()
        assert(controller.status == .scheduled)
        adapter.authorization = .unavailable
        await controller.refresh()
        assert(controller.status == .failed && controller.errorMessage != nil)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == nil)
        await controller.setEnabled(false)
        assert(controller.status == .disabled && controller.errorMessage == nil && !controller.needsSettings)
        assert(adapter.permissionRequests == 1)
    }

    @MainActor
    private static func checkFailuresAndRecovery() async throws {
        let defaults = ReminderMemoryDefaults()
        let corrupt = Data("invalid reminder data".utf8)
        defaults.set(corrupt, forKey: ReminderPreferences.storageKey)
        let adapter = FakeReminderNotifications()
        adapter.pending[ReminderPreferences.notificationIdentifier] = .standard
        let controller = ReminderController(defaults: defaults, notifications: adapter)
        assert(controller.status == .failed && controller.preferences == .standard)
        await controller.refresh()
        assert(controller.status == .failed && controller.errorMessage != nil)
        assert(defaults.data(forKey: ReminderPreferences.storageKey) == corrupt, "Do not overwrite corrupt data on launch")
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == nil && adapter.permissionRequests == 0)

        adapter.rejectPermission = true
        await controller.setEnabled(true)
        assert(controller.status == .failed && controller.errorMessage != nil)
        assert(adapter.permissionRequests == 1 && adapter.added.isEmpty)
        adapter.rejectPermission = false
        await controller.setEnabled(true)
        assert(controller.status == .scheduled && controller.errorMessage == nil)
        adapter.rejectSchedule = true
        await controller.setTime(localTime(hour: 13, minute: 25))
        assert(controller.preferences.hour == 13 && controller.preferences.minute == 25)
        assert(controller.status == .failed && controller.errorMessage != nil)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == nil, "A failed replacement must remove the old time")
        adapter.rejectSchedule = false
        await controller.refresh()
        assert(controller.status == .scheduled && controller.errorMessage == nil)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == controller.preferences)
        assert(adapter.permissionRequests == 2)
    }

    @MainActor
    private static func checkSerializedChanges() async throws {
        let adapter = FakeReminderNotifications()
        adapter.authorization = .authorized
        let controller = ReminderController(defaults: ReminderMemoryDefaults(), notifications: adapter)
        let gate = ReminderTestGate()
        adapter.nextAddGate = gate
        let enable = Task { await controller.setEnabled(true) }
        await gate.waitUntilEntered()
        assert(controller.isUpdating)
        let reads = adapter.authorizationReads
        await controller.refresh()
        assert(adapter.authorizationReads == reads, "A refresh must not race a user update")
        var timeChangeStarted = false
        let timeChange = Task {
            timeChangeStarted = true
            await controller.setTime(localTime(hour: 19, minute: 40))
        }
        while !timeChangeStarted { await Task.yield() }
        var disableStarted = false
        let disable = Task {
            disableStarted = true
            await controller.setEnabled(false)
        }
        while !disableStarted { await Task.yield() }
        assert(controller.preferences.hour == 8 && controller.preferences.isEnabled)
        gate.release()
        await enable.value
        await timeChange.value
        await disable.value
        assert(adapter.added.count == 2 && adapter.added[0].hour == 8 && adapter.added[1].hour == 19)
        assert(controller.preferences.hour == 19 && controller.preferences.minute == 40)
        assert(!controller.preferences.isEnabled && controller.status == .disabled && !controller.isUpdating)
        assert(adapter.pending[ReminderPreferences.notificationIdentifier] == nil)
        assert(adapter.permissionRequests == 0)
    }

    @MainActor
    private static func checkTapRouting() async {
        let adapter = FakeReminderNotifications()
        let controller = ReminderController(defaults: ReminderMemoryDefaults(), notifications: adapter)
        controller.configure()
        adapter.tap()
        assert(controller.openTasbihRequest == 1, "A tap received before the content view appears must remain observable")
        controller.configure()
        adapter.tap()
        assert(controller.openTasbihRequest == 2 && adapter.installCount == 1)
        var opens = 0
        let delegate = ReminderNotificationDelegate { opens += 1 }
        await delegate.receive(requestIdentifier: "unrelated.pending", actionIdentifier: UNNotificationDefaultActionIdentifier)
        await delegate.receive(requestIdentifier: ReminderPreferences.notificationIdentifier, actionIdentifier: UNNotificationDismissActionIdentifier)
        await delegate.receive(requestIdentifier: ReminderPreferences.notificationIdentifier, actionIdentifier: "unrelated.action")
        assert(opens == 0)
        await delegate.receive(requestIdentifier: ReminderPreferences.notificationIdentifier, actionIdentifier: UNNotificationDefaultActionIdentifier)
        assert(opens == 1)
    }

    @MainActor
    private static func localTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute))!
    }
}
