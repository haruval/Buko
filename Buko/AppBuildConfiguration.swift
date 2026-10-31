import Foundation

/// Normal and isolated builds explicitly enable layout through their plists.
/// Missing configuration stays on the original reader/planner; the baseline
/// launch argument selects that path without changing the app identity.
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
