import Foundation

nonisolated struct ReminderPreferences: Codable, Equatable, Sendable {
    static let storageKey = "rosery.reminders.v1"
    static let notificationIdentifier = "rosery.reminder.daily"
    static let standard = ReminderPreferences()

    var isEnabled = false
    private(set) var hour = 8
    private(set) var minute = 0

    init() {}

    init(isEnabled: Bool, hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw ValidationError.invalidTime
        }
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, hour, minute }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(isEnabled: values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
                      hour: values.decodeIfPresent(Int.self, forKey: .hour) ?? 8,
                      minute: values.decodeIfPresent(Int.self, forKey: .minute) ?? 0)
    }

    /// Omitting a time zone keeps the repeating notification tied to the device's local clock.
    var dateComponents: DateComponents { DateComponents(hour: hour, minute: minute) }

    enum ValidationError: Error { case invalidTime }
}

nonisolated enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unavailable
}

nonisolated enum ReminderScheduleDecision: Equatable, Sendable {
    case cancel, requestPermission, needsPermission, blocked, schedule(quietly: Bool), unavailable

    static func make(isEnabled: Bool, authorization: ReminderAuthorization,
                     mayRequestPermission: Bool) -> Self {
        guard isEnabled else { return .cancel }
        switch authorization {
        case .notDetermined: return mayRequestPermission ? .requestPermission : .needsPermission
        case .denied: return .blocked
        case .authorized, .ephemeral: return .schedule(quietly: false)
        case .provisional: return .schedule(quietly: true)
        case .unavailable: return .unavailable
        }
    }
}
