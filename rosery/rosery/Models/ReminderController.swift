import Foundation
import Observation
import OSLog
import UserNotifications

nonisolated enum ReminderStatus: Equatable, Sendable {
    case disabled, needsPermission, blocked, scheduled, scheduledQuietly, failed
}

@MainActor
protocol ReminderNotificationAdapter: AnyObject {
    func installTapHandler(_ handler: @escaping @MainActor @Sendable () -> Void)
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func addDailyReminder(_ preferences: ReminderPreferences) async throws
    func removePending(identifiers: [String])
    func removeDelivered(identifiers: [String])
}

@MainActor
@Observable
final class ReminderController {
    private(set) var preferences: ReminderPreferences
    private(set) var status = ReminderStatus.disabled
    private(set) var errorMessage: String?
    private(set) var isUpdating = false
    private(set) var openTasbihRequest: UInt64 = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifications: any ReminderNotificationAdapter
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var loadError: String?
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard, notifications: (any ReminderNotificationAdapter)? = nil) {
        self.defaults = defaults
        self.notifications = notifications ?? SystemReminderNotificationAdapter()
        do {
            preferences = try defaults.data(forKey: ReminderPreferences.storageKey)
                .map { try JSONDecoder().decode(ReminderPreferences.self, from: $0) } ?? .standard
        } catch {
            preferences = .standard
            let message = "Your reminder settings couldn’t be read. Choose a time and turn the reminder on again."
            loadError = message
            errorMessage = message
            status = .failed
        }
    }

    /// Install before app launch finishes; this controller keeps the notification delegate alive.
    func configure() {
        guard !configured else { return }
        configured = true
        notifications.installTapHandler { [weak self] in
            self?.openTasbihRequest += 1
        }
    }

    var time: Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15,
                                                   hour: preferences.hour, minute: preferences.minute)) ?? .now
    }

    var needsSettings: Bool { preferences.isEnabled && status == .blocked }

    var summary: String {
        if isUpdating { return "Updating reminder…" }
        switch status {
        case .disabled: return "Off"
        case .needsPermission: return "Notification permission is needed"
        case .blocked: return "Notifications are off in Settings"
        case .scheduled: return "Every day at \(time.formatted(date: .omitted, time: .shortened))"
        case .scheduledQuietly: return "Daily at \(time.formatted(date: .omitted, time: .shortened)), delivered quietly"
        case .failed: return "Reminder isn’t scheduled"
        }
    }

    /// Foreground/time-zone refreshes never trigger a permission prompt.
    func refresh() async {
        guard !isUpdating else { return }
        await acquireOperation()
        defer { finishOperation() }
        await reconcile(mayRequestPermission: false)
    }

    /// Only explicit opt-in can ask the system for notification permission.
    func setEnabled(_ enabled: Bool) async {
        await acquireOperation()
        defer { finishOperation() }
        preferences.isEnabled = enabled
        guard savePreferences() else { return }
        await reconcile(mayRequestPermission: enabled)
    }

    func setTime(_ date: Date) async {
        await acquireOperation()
        defer { finishOperation() }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        do {
            preferences = try ReminderPreferences(isEnabled: preferences.isEnabled,
                                                  hour: components.hour ?? 8, minute: components.minute ?? 0)
            guard savePreferences() else { return }
            await reconcile(mayRequestPermission: false)
        } catch {
            fail("That time couldn’t be saved. Please choose another time.")
        }
    }

    private func reconcile(mayRequestPermission: Bool) async {
        errorMessage = loadError
        guard preferences.isEnabled else {
            cancelOwnReminder()
            status = loadError == nil ? .disabled : .failed
            return
        }

        var authorization = await notifications.authorizationStatus()
        var decision = ReminderScheduleDecision.make(isEnabled: true, authorization: authorization,
                                                      mayRequestPermission: mayRequestPermission)
        if decision == .requestPermission {
            do {
                _ = try await notifications.requestAuthorization()
                // Permission may have been denied or changed while the prompt was open.
                authorization = await notifications.authorizationStatus()
                decision = ReminderScheduleDecision.make(isEnabled: true, authorization: authorization,
                                                          mayRequestPermission: false)
            } catch {
                fail("Notification permission couldn’t be checked. Please try again.")
                return
            }
        }

        switch decision {
        case .schedule(let quietly):
            do {
                // UNUserNotificationCenter replaces a pending request with this stable identifier.
                try await notifications.addDailyReminder(preferences)
                status = quietly ? .scheduledQuietly : .scheduled
            } catch {
                // Remove any old time after a rejected replacement; do not report it as the new schedule.
                fail("Your reminder couldn’t be scheduled. Please try again.")
            }
        case .needsPermission, .requestPermission:
            cancelOwnReminder()
            status = .needsPermission
        case .blocked:
            cancelOwnReminder()
            status = .blocked
        case .unavailable:
            fail("Notification settings couldn’t be checked. Please try again.")
        case .cancel:
            cancelOwnReminder()
            status = .disabled
        }
    }

    private func savePreferences() -> Bool {
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: ReminderPreferences.storageKey)
            loadError = nil
            errorMessage = nil
            return true
        } catch {
            fail("Your reminder settings couldn’t be saved. Please try again.")
            return false
        }
    }

    private func cancelOwnReminder() {
        let identifiers = [ReminderPreferences.notificationIdentifier]
        notifications.removePending(identifiers: identifiers)
        notifications.removeDelivered(identifiers: identifiers)
    }

    private func fail(_ message: String) {
        cancelOwnReminder()
        errorMessage = message
        status = .failed
    }

    /// Serialize permission and scheduling operations across suspension points.
    private func acquireOperation() async {
        if isUpdating {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isUpdating = true
        }
    }

    private func finishOperation() {
        if waiters.isEmpty {
            isUpdating = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class SystemReminderNotificationAdapter: ReminderNotificationAdapter {
    private static let logger = Logger(subsystem: "mujhtech.rosery", category: "Reminders")
    private let center: UNUserNotificationCenter
    private var delegate: ReminderNotificationDelegate?

    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func installTapHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        let delegate = ReminderNotificationDelegate(onOpenTasbih: handler)
        self.delegate = delegate
        center.delegate = delegate
    }

    func authorizationStatus() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unavailable
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func addDailyReminder(_ preferences: ReminderPreferences) async throws {
        let request = Self.request(for: preferences)
        do {
            try await center.add(request)
        } catch {
            let nativeError = error as NSError
            let hasNextDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() != nil
            Self.logger.error("Daily reminder scheduling failed: domain=\(nativeError.domain, privacy: .public), code=\(nativeError.code), hasNextDate=\(hasNextDate)")
            if let underlying = nativeError.userInfo[NSUnderlyingErrorKey] as? NSError {
                Self.logger.error("Underlying scheduling error: domain=\(underlying.domain, privacy: .public), code=\(underlying.code)")
            }
            throw error
        }
    }

    func removePending(identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }

    static func request(for preferences: ReminderPreferences) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "A moment of remembrance"
        content.body = "Pause for dhikr. Your tasbih is ready."
        content.sound = .default
        content.threadIdentifier = "rosery.reminders"
        content.userInfo = ["route": "tasbih"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: preferences.dateComponents, repeats: true)
        return UNNotificationRequest(identifier: ReminderPreferences.notificationIdentifier, content: content, trigger: trigger)
    }
}

nonisolated final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let onOpenTasbih: @MainActor @Sendable () -> Void

    init(onOpenTasbih: @escaping @MainActor @Sendable () -> Void) {
        self.onOpenTasbih = onOpenTasbih
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == ReminderPreferences.notificationIdentifier ? [.banner, .list, .sound] : []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await receive(requestIdentifier: response.notification.request.identifier, actionIdentifier: response.actionIdentifier)
    }

    func receive(requestIdentifier: String, actionIdentifier: String) async {
        guard requestIdentifier == ReminderPreferences.notificationIdentifier,
              actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await onOpenTasbih()
    }
}
