import Foundation

/// Build defaults are explicit; a normal build without these keys stays on the
/// original reader/planner. The isolated app enables layout through its plist.
nonisolated enum AppBuildConfiguration {
    static var isIsolatedExperiment: Bool {
        Bundle.main.object(forInfoDictionaryKey: "BukoIsolatedExperiment") as? Bool ?? false
    }

    static func capturePlanningMode() -> AutofillPlanningMode {
        .resolve(enabled: Bundle.main.object(forInfoDictionaryKey: "BukoLayoutAutofillEnabled") as? Bool ?? false,
                 arguments: ProcessInfo.processInfo.arguments)
    }
}

nonisolated enum AutofillPlanningMode: Sendable {
    case standard, layoutAware

    static func resolve(enabled: Bool = false, arguments: [String] = []) -> Self {
        enabled && !arguments.contains("--spatial-baseline") ? .layoutAware : .standard
    }
}
