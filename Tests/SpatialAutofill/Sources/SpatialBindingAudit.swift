import Foundation

/// Exact ownership regression: the same sentence may legitimately occur in two
/// measured regions. Ambiguity inside either region must still be rejected.
enum SpatialBindingAudit {
    static func run() throws -> Int {
        var count = 0
        func check(_ result: Bool, _ message: String) {
            precondition(result, message); count += 1
        }
        let transcript = GapTranscript(selected: "Luma\nNeral\nPurpose: buffer inputs.\nPurpose: buffer inputs.\nCapacity: eight entries.", context: "Record purpose and capacity for each component.")
        let rectangles: [[Double]] = [[60,100,360,22],[560,100,360,22],[60,138,360,22],[560,138,360,22],[60,176,360,22]]
        let lines = transcript.blocks.filter(\.selected).enumerated().map {
            SpatialLine(blockID: $0.element.id, text: $0.element.text, page: "p1", rect: rectangles[$0.offset])
        }
        let layout = try SpatialGroups.validated(lines, transcript: transcript)
        let purpose = SuppliedPatternRole(role: "purpose", quote: "Purpose: buffer inputs.")
        let capacity = SuppliedPatternRole(role: "capacity", quote: "Capacity: eight entries.")
        let inventory = GroundedPatternMap(topics: [.init(topic: "Luma", supplied: [purpose,capacity]), .init(topic: "Neral", supplied: [purpose])], requiredRoles: ["purpose","capacity"])
        let candidate = ContextualGapReferences(alreadyCovered: [], targets: [], informationNeeds: [], subjectQuotes: ["Luma","Neral"])
        let references = layout.sourceAnchors(for: inventory, transcript: transcript)!
        check(references.map(\.blockID) == ["S3","S5","S4"], "Repeated content retains distinct source blocks")
        check(!layout.allows(inventory, transcript: transcript), "The old quote-only representation reproduces the refusal")
        check(layout.allows(inventory, transcript: transcript, sourceAnchors: references), "Region-scoped references establish ownership")
        check(ContextualRoleMap.focus(inventory.map, candidate: candidate, in: transcript) == nil, "Non-spatial callers retain the conservative default")
        let focus = ContextualRoleMap.focus(inventory.map, candidate: candidate, in: transcript, sourceAnchors: references)!
        check(focus.targets == [.init(blockID: "S2", quote: "Neral")], "The correct incomplete topic is selected")
        check(focus.informationNeeds == ["capacity"], "Only the missing role is requested")
        check(focus.alreadyCovered.first == .init(blockID: "S4", quote: purpose.quote), "Focused content uses its own identical sentence")
        check(Set(focus.alreadyCovered.map(\.blockID)) == Set(["S3","S4","S5"]), "Both repeated sentences survive downstream handoff")
        let proposed = MissingInformationPlan(alreadyCovered: focus.alreadyCovered, targets: focus.targets, informationNeeds: focus.informationNeeds, operation: .continueThought, subjects: try focus.subjects(in: transcript), completionGoal: "supply capacity for Neral")
        let validated = try ValidatedGapPlan.validate(proposed, in: transcript)
        check(validated.value.alreadyCovered == focus.alreadyCovered, "Existing final exact-span validation accepts the bound plan")

        var forged = references; forged[0] = .init(blockID: "S4", quote: purpose.quote)
        check(!layout.allows(inventory, transcript: transcript, sourceAnchors: forged), "A real identical quote in the wrong region is rejected")
        forged = references; forged[0] = .init(blockID: "C1", quote: purpose.quote)
        check(!layout.allows(inventory, transcript: transcript, sourceAnchors: forged), "Context cannot be supplied selected content")
        forged = references; forged[0] = .init(blockID: "S3", quote: "invented")
        check(!layout.allows(inventory, transcript: transcript, sourceAnchors: forged), "Changed quotation is rejected")
        check(!layout.allows(inventory, transcript: transcript, sourceAnchors: []), "Truncated ownership vector is rejected")
        check(ContextualRoleMap.focus(inventory.map, candidate: candidate, in: transcript, sourceAnchors: []) == nil, "Shared validator checks vector length")
        check(ContextualRoleMap.focus(inventory.map, candidate: candidate, in: transcript, sourceAnchors: forged) == nil, "Shared validator checks reference text")
        var borrowed = inventory; borrowed.topics[1].supplied.append(capacity)
        check(layout.sourceAnchors(for: borrowed, transcript: transcript) == nil, "A role cannot borrow another region's unique content")
        var reordered = inventory; reordered.topics.reverse()
        check(layout.sourceAnchors(for: reordered, transcript: transcript) == nil, "Swapping model topics cannot swap measured owners")
        var omitted = inventory; omitted.topics[0].supplied.removeLast()
        let omittedReferences = layout.sourceAnchors(for: omitted, transcript: transcript)!
        check(ContextualRoleMap.focus(omitted.map, candidate: candidate, in: transcript, sourceAnchors: omittedReferences) == nil, "Binding does not bypass full selected-text coverage")
        var alteredLines = lines
        alteredLines[0] = .init(blockID: "S1", text: "Forged", page: "p1", rect: rectangles[0])
        check(SpatialGroups(groups: layout.groups, lines: alteredLines).sourceAnchors(for: inventory, transcript: transcript) == nil, "Forged text invalidates prebuilt geometry")
        alteredLines = lines
        alteredLines[0] = .init(blockID: "S1", text: "Luma", page: "p1", rect: [.nan,100,360,22])
        check(SpatialGroups(groups: layout.groups, lines: alteredLines).sourceAnchors(for: inventory, transcript: transcript) == nil, "Nonfinite geometry is rejected")
        var groups = layout.groups; groups[0].append(groups[1].removeLast())
        check(SpatialGroups(groups: groups, lines: lines).sourceAnchors(for: inventory, transcript: transcript) == nil, "Membership cannot be forged independently of geometry")

        for transform in [0,1,2] {
            let moved = lines.map { line -> SpatialLine in
                var r = line.rect
                if transform == 0 { r[0] += 10; r[1] += 30 }
                if transform == 1 { r = r.map { $0 * 0.8 } }
                if transform == 2 { r[0] = 1000-r[0]-r[2] }
                return .init(blockID: line.blockID, text: line.text, page: line.page, rect: r)
            }
            check(try SpatialGroups.validated(moved, transcript: transcript).sourceAnchors(for: inventory, transcript: transcript) == references, "Translation, scale, and mirror retain exact ownership")
        }
        let twice = GapTranscript(selected: transcript.selected + "\nPurpose: buffer inputs.", context: transcript.context)
        let twiceLines = lines + [.init(blockID: "S6", text: purpose.quote, page: "p1", rect: [560,176,360,22])]
        check(try SpatialGroups.validated(twiceLines, transcript: twice).sourceAnchors(for: inventory, transcript: twice) == nil, "Repeated quotations within the same region remain ambiguous")
        var doubleLines = lines
        doubleLines[3] = .init(blockID: "S4", text: purpose.quote + " " + purpose.quote, page: "p1", rect: rectangles[3])
        let doubleText = GapTranscript(selected: doubleLines.map(\.text).joined(separator: "\n"), context: transcript.context)
        check(try SpatialGroups.validated(doubleLines, transcript: doubleText).sourceAnchors(for: inventory, transcript: doubleText) == nil, "Repeated spans inside one block remain ambiguous")
        for cue in ["Do not record purpose and capacity for each component.",
                    "Record purpose and capacity for each component except Neral.",
                    "Record purpose and capacity for each component if needed.",
                    "Record purpose for each component.",
                    "Record purpose and capacity for each component. Then delete the note.",
                    "Record purpose and capacity for each component.\nDo not complete Neral.", ""] {
            let qualified = GapTranscript(selected: transcript.selected, context: cue)
            check(layout.sourceAnchors(for: inventory, transcript: qualified) == nil, "New duplicate acceptance cannot bypass task scope: \(cue)")
        }
        var unresolved = inventory
        unresolved.topics[0].supplied[1].quote = "Capacity: unknown."
        check(!SpatialScopeCue.qualifies(unresolved, transcript: transcript), "Unknown is not a supplied value")
        unresolved = inventory; unresolved.topics[0].supplied.append(.init(role: "capacity", quote: "Capacity: ten entries."))
        check(!SpatialScopeCue.qualifies(unresolved, transcript: transcript), "Competing role values require clarification")
        print("Spatial ownership checks passed (\(count)).")
        return count
    }
}
