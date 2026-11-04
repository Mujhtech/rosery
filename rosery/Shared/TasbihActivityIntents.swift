#if os(iOS)
import AppIntents

/// Kept under its original name for installed Home Screen widgets. LiveActivityIntent makes
/// every count mutation and its ActivityKit synchronization execute in the same app process.
@MainActor
struct IncrementTasbihIntent: LiveActivityIntent {
    nonisolated static let title: LocalizedStringResource = "Add One Remembrance"
    nonisolated static let description = IntentDescription("Add one to the current tasbih count without opening Rosery.")
    nonisolated static let openAppWhenRun = false
    nonisolated static let isDiscoverable = false
    nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, *) nonisolated static var supportedModes: IntentModes { .background }

    @Parameter(title: "Dhikr") var expectedDhikrID: String
    @Parameter(title: "Round") var expectedGeneration: String

    nonisolated static var parameterSummary: some ParameterSummary { Summary("Add one remembrance") }
    nonisolated init() {}
    init(snapshot: TasbihSnapshot) {
        expectedDhikrID = snapshot.selectedID
        expectedGeneration = snapshot.generation
    }

    func perform() async throws -> some IntentResult {
        _ = await TasbihActivityCoordinator.shared.change(.increment, expectedID: expectedDhikrID,
                                                         generation: expectedGeneration, requiresActivity: false)
        return .result()
    }
}

@MainActor
struct IncrementTasbihLiveActivityIntent: LiveActivityIntent {
    nonisolated static let title: LocalizedStringResource = "Count One Remembrance"
    nonisolated static let description = IntentDescription("Add one remembrance to this Live Activity’s current round.")
    nonisolated static let openAppWhenRun = false
    nonisolated static let isDiscoverable = false
    nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, *) nonisolated static var supportedModes: IntentModes { .background }

    @Parameter(title: "Dhikr") var expectedID: String
    @Parameter(title: "Round") var generation: String

    nonisolated static var parameterSummary: some ParameterSummary { Summary("Count one remembrance") }
    nonisolated init() {}
    init(expectedID: String, generation: String) {
        self.expectedID = expectedID
        self.generation = generation
    }

    func perform() async throws -> some IntentResult {
        _ = await TasbihActivityCoordinator.shared.change(.increment, expectedID: expectedID,
                                                         generation: generation, requiresActivity: true)
        return .result()
    }
}

@MainActor
struct UndoTasbihLiveActivityIntent: LiveActivityIntent {
    nonisolated static let title: LocalizedStringResource = "Undo One Remembrance"
    nonisolated static let description = IntentDescription("Undo the last count in this Live Activity’s current round.")
    nonisolated static let openAppWhenRun = false
    nonisolated static let isDiscoverable = false
    nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, *) nonisolated static var supportedModes: IntentModes { .background }

    @Parameter(title: "Dhikr") var expectedID: String
    @Parameter(title: "Round") var generation: String

    nonisolated static var parameterSummary: some ParameterSummary { Summary("Undo one remembrance") }
    nonisolated init() {}
    init(expectedID: String, generation: String) {
        self.expectedID = expectedID
        self.generation = generation
    }

    func perform() async throws -> some IntentResult {
        _ = await TasbihActivityCoordinator.shared.change(.undo, expectedID: expectedID,
                                                         generation: generation, requiresActivity: true)
        return .result()
    }
}

@MainActor
struct StopTasbihLiveActivityIntent: LiveActivityIntent {
    nonisolated static let title: LocalizedStringResource = "End Live Activity"
    nonisolated static let description = IntentDescription("Remove this tasbih Live Activity while keeping its saved count.")
    nonisolated static let openAppWhenRun = false
    nonisolated static let isDiscoverable = false
    nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, *) nonisolated static var supportedModes: IntentModes { .background }

    @Parameter(title: "Dhikr") var expectedID: String
    @Parameter(title: "Round") var generation: String

    nonisolated static var parameterSummary: some ParameterSummary { Summary("End this Live Activity") }
    nonisolated init() {}
    init(expectedID: String, generation: String) {
        self.expectedID = expectedID
        self.generation = generation
    }

    func perform() async throws -> some IntentResult {
        _ = await TasbihActivityCoordinator.shared.stop(expectedID: expectedID, generation: generation)
        return .result()
    }
}
#endif
