import Foundation

/// A retrieved worked example must never replace arithmetic on the selected operands.
nonisolated enum CircleCompletionRoute {
    case arithmetic(MatrixProductCheck.Result)
    case lecture
    case noEvidence

    static func select(for selected: String, hasLectureEvidence: Bool) -> Self {
        if let result = MatrixProductCheck.evaluate(selected) { return .arithmetic(result) }
        if MatrixProductCheck.isUnfinishedRequest(selected) {
            return .arithmetic(.init(lines: [], clarification:
                "Please confirm both matrices and every numeric entry. Local calculation supports at most 4 rows and 4 columns per matrix."))
        }
        return hasLectureEvidence ? .lecture : .noEvidence
    }
}
