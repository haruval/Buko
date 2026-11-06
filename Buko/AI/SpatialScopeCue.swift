import Foundation

/// Conservative eligibility for accepting previously ambiguous repeated text.
/// A whole, positive task cue must name every required role. This is deliberately
/// not a general natural-language scope classifier; unsupported cues keep the
/// existing refusal behavior and do not receive a broader interpretation.
nonisolated enum SpatialScopeCue {
    static func qualifies(_ inventory: GroundedPatternMap, transcript: GapTranscript) -> Bool {
        let context = transcript.blocks.filter { !$0.selected }
        let labels = inventory.requiredRoles.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard context.count == 1, (2...4).contains(labels.count), Set(labels).count == labels.count,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 120 }),
              matches(context[0].text, labels: labels) else { return false }
        let placeholders: Set<String> = ["unknown", "tbd", "todo", "not sure", "not known", "not specified", "don’t know", "don't know", "do not know", "unsure", "blank", "pending"]
        for topic in inventory.topics {
            // Multiple competing values for one role need semantic review.
            let roles = topic.supplied.map { $0.role.trimmingCharacters(in: .whitespaces).lowercased() }
            guard Set(roles).count == roles.count else { return false }
            for role in topic.supplied {
                let value = role.quote.split(separator: ":", maxSplits: 1).last.map(String.init) ?? role.quote
                guard !value.contains("?"), !placeholders.contains(value.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))) else { return false }
            }
        }
        return true
    }

    static func matches(_ cue: String, labels: [String]) -> Bool {
        func permutations(_ items: [String]) -> [[String]] {
            if items.count <= 1 { return [items] }
            return items.indices.flatMap { i in permutations(Array(items[..<i]) + Array(items[(i+1)...])).map { [items[i]] + $0 } }
        }
        let noun = "[\\p{L}][\\p{L}-]{0,40}"
        let verbs = "(?:record|write|list|give)"
        for order in permutations(labels) {
            let escaped = order.map(NSRegularExpression.escapedPattern)
            let fieldList = escaped.count == 2 ? escaped.joined(separator: "\\s+and\\s+")
                : escaped.dropLast().joined(separator: "\\s*,\\s*") + "\\s*,?\\s+and\\s+" + escaped.last!
            let forms = [
                "for\\s+(?:each|every)\\s+" + noun + ",\\s*" + verbs + "\\s+(?:its\\s+|the\\s+)?" + fieldList,
                verbs + "\\s+(?:the\\s+)?" + fieldList + "\\s+for\\s+(?:each|every)\\s+" + noun,
                verbs + "\\s+each\\s+" + noun + "['’]s\\s+" + fieldList
            ]
            if forms.contains(where: { cue.range(of: "^\\s*" + $0 + "[.!]?\\s*$", options: [.regularExpression, .caseInsensitive]) != nil }) { return true }
        }
        return false
    }

}
