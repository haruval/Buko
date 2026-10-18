import Foundation

/// Conservative arithmetic support for an explicit unfinished product such as
/// C = [2 1; 0 3], D = [1 4; 2 0]. CD = . No OCR/layout guessing.
nonisolated enum MatrixProductCheck {
    private static let unfinishedProduct = #"\b([A-Za-z])\s*([A-Za-z])\s*=\s*$"#

    struct Result {
        let lines: [String]
        let clarification: String
    }

    static func evaluate(_ selected: String) -> Result? {
        let text = selected.replacingOccurrences(of: "−", with: "-")
        guard let target = matches(unfinishedProduct, in: text).last else { return nil }
        var matrices: [String: [[Double]]] = [:]
        for assignment in matches(#"\b([A-Za-z])\s*=\s*\[([^\[\]]+)\]"#, in: text) {
            let name = assignment[1].lowercased()
            // Repeated bindings are ambiguous; do not pick one silently.
            guard matrices[name] == nil else { return nil }
            let rows = assignment[2].components(separatedBy: ";")
            guard (1...4).contains(rows.count) else { return nil }
            var values: [[Double]] = []
            for row in rows {
                let fields = row.split { $0.isWhitespace || $0 == "," }
                guard (1...4).contains(fields.count) else { return nil }
                let numbers = fields.compactMap { Double($0) }
                guard numbers.count == fields.count, numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return nil }
                values.append(numbers)
            }
            guard values.allSatisfy({ $0.count == values[0].count }) else { return nil }
            matrices[name] = values
        }
        guard let left = matrices[target[1].lowercased()], let right = matrices[target[2].lowercased()] else { return nil }
        guard left[0].count == right.count else {
            return Result(lines: [], clarification: "The left matrix has \(left[0].count) columns, but the right matrix has \(right.count) rows. Please confirm the matrices or the multiplication order.")
        }
        var result: [[Double]] = []
        var lines: [String] = []
        for row in left.indices {
            var entries: [Double] = []
            var calculations: [String] = []
            for column in right[0].indices {
                let value = left[row].indices.reduce(0.0) { $0 + left[row][$1] * right[$1][column] }
                entries.append(value)
                let terms = left[row].indices.map { "(\(number(left[row][$0])) * \(number(right[$0][column])))" }
                calculations.append(terms.joined(separator: " + ") + " = " + number(value))
            }
            result.append(entries)
            lines.append("Row \(row + 1): " + calculations.joined(separator: "; ") + ".")
        }
        let name = target[1] + target[2]
        lines.append(name + " = [" + result.map { $0.map(number).joined(separator: " ") }.joined(separator: "; ") + "].")
        return Result(lines: lines, clarification: "")
    }

    static func isUnfinishedRequest(_ selected: String) -> Bool {
        // A recognizable matrix request with missing/ambiguous operands must not
        // fall through to a model that can substitute a retrieved example.
        !matches(unfinishedProduct, in: selected).isEmpty
            && !matches(#"\b[A-Za-z]\s*=\s*\["#, in: selected).isEmpty
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }
}
