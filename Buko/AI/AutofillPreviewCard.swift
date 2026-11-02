import SwiftUI

enum AutofillPreviewStage {
    case thinking, working, finished, unavailable

    init(_ state: CircleIntentState) {
        if state.proposal != nil { self = .finished }
        else if state.processing { self = state.missingInformation == nil ? .thinking : .working }
        else { self = .unavailable }
    }
}

struct AutofillPreviewCard: View {
    let state: CircleIntentState
    let detailed: Bool
    let maximumHeight: CGFloat
    var dragTitle: ((CGSize?) -> Void)? = nil
    let sizeChanged: (CGSize) -> Void
    @State private var headerHeight: CGFloat = 44
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sourcePreview: LecturePDFDestination?
    @State private var sourceError: String?
    @State private var sourceTask: Task<Void, Never>?
    @State private var clarificationReply = ""
    @FocusState private var clarificationFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                header
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { headerHeight = $0 }
                if hasContent {
                    ScrollView {
                        previewContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { contentHeight = $0 }
                    }
                    .frame(height: min(contentHeight, max(44, maximumHeight - fixedHeight)))
                    .scrollBounceBehavior(.basedOnSize)
                    .transition(resultTransition)
                }
                if hasFooter {
                    VStack(alignment: .leading, spacing: 10) {
                        if let sourceError { Text(sourceError).font(.caption).foregroundStyle(.red) }
                        if let issue = state.insertion.issue {
                            Text(issue).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("autofillInsertionIssue")
                        }
                        if state.proposal != nil { acceptance }
                        if state.canClarify { clarificationInput }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { footerHeight = $0 }
                    .transition(resultTransition)
                }
            }
            .padding(16)
            .fixedSize(horizontal: false, vertical: true)
        }
        // The outer animated frame proposes its previous height. Measure the
        // intrinsic sections instead so newly loaded source crops and controls
        // enlarge both the glass clip and UIKit's touch boundary.
        .onAppear { sizeChanged(CGSize(width: 0, height: desiredHeight)) }
        .onChange(of: desiredHeight) { _, height in sizeChanged(CGSize(width: 0, height: height)) }
        .fullScreenCover(item: $sourcePreview) { LecturePDFView(destination: $0) }
        .onDisappear { sourceTask?.cancel() }
        .onChange(of: state.canClarify) { _, ready in
            if ready { clarificationReply = "" }
        }
    }

    private var hasContent: Bool {
        if detailed { return true }
        if let proposal = state.proposal { return !proposal.usedCitations.isEmpty || proposal.content.origin == .localArithmetic }
        return !state.processing
    }
    private var hasFooter: Bool { state.proposal != nil || state.canClarify || sourceError != nil || state.insertion.issue != nil }
    private var fixedHeight: CGFloat {
        32 + headerHeight + (hasContent ? 12 : 0) + (hasFooter ? footerHeight + 12 : 0)
    }
    private var desiredHeight: CGFloat {
        ceil(fixedHeight + (hasContent ? min(contentHeight, max(44, maximumHeight - fixedHeight)) : 0))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if state.processing && !detailed {
                ProgressView().controlSize(.small).frame(width: 20)
                    .accessibilityLabel(state.progressLabel)
            }
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .leading) {
                    Text(detailed ? "Autofill preview" : title)
                        .font(.headline).lineLimit(detailed ? nil : 3).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("autofillPreviewTitle")
                        .id(detailed ? "Autofill preview" : title)
                        .transition(titleTransition)
                }
                .animation(stageAnimation, value: title)
                if detailed && state.processing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(state.progressLabel).font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("autofillOverlay"))
                .onChanged { dragTitle?($0.translation) }
                .onEnded { _ in dragTitle?(nil) })
            .accessibilityHint("Drag to move the preview")
            Spacer(minLength: 0)
            Button(action: state.decline) {
                Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityLabel("Dismiss autofill")
        }
    }

    @ViewBuilder private var previewContent: some View {
        if detailed {
            VStack(alignment: .leading, spacing: 18) {
                DetailedAutofillPreview(state: state)
                if !state.citations.isEmpty { sources(state.citations, title: "Approved lecture evidence") }
                if !state.retrievedHits.isEmpty {
                    DisclosureGroup("Retrieved lecture passages (\(state.retrievedHits.count))") {
                        ForEach(Array(state.retrievedHits.enumerated()), id: \.element.id) { index, hit in
                            source(hit.passage, quote: hit.passage.text, prefix: "P\(index + 1) · ")
                                .padding(.top, 8)
                        }
                    }.font(.subheadline.weight(.medium))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("retrievedLecturePassages")
                }
            }
        } else if let proposal = state.proposal {
            if !proposal.usedCitations.isEmpty { sources(proposal.usedCitations, title: "Sources") }
            else if proposal.content.origin == .localArithmetic {
                Text("Calculated on this iPad from the matrices in your notes.").font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(finishedMessage).font(.subheadline).textSelection(.enabled)
                    .accessibilityIdentifier("autofillUnavailable")
            }
        }
    }

    private var clarificationInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("A little more detail…", text: $clarificationReply, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain)
                    .padding(.leading, 16).padding(.vertical, 12)
                    .focused($clarificationFocused).submitLabel(.send)
                    .accessibilityIdentifier("autofillClarificationInput")
                    .onSubmit(submitClarification)
                Button(action: submitClarification) {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(.blue)
                .accessibilityLabel("Send clarification")
                .disabled(clarificationReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clarificationReply.count > 500)
                .accessibilityIdentifier("submitAutofillClarification")
                .padding(4)
            }
            .glassEffect(.clear.interactive(), in: .capsule)
            if let issue = state.clarificationIssue { Text(issue).font(.caption).foregroundStyle(.red) }
            if clarificationReply.count > 500 { Text("Use 500 characters or fewer.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func submitClarification() {
        clarificationFocused = false
        state.submitClarification(clarificationReply)
    }

    private var stageAnimation: Animation? {
        detailed || reduceMotion ? nil : CircleAIStyle.previewSpring
    }

    private var titleTransition: AnyTransition {
        guard !detailed, !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98, anchor: .leading)),
            removal: .opacity.combined(with: .offset(y: -5)))
    }

    private var resultTransition: AnyTransition {
        detailed || reduceMotion ? .identity : .opacity.combined(with: .offset(y: 12))
    }

    private var title: String {
        if let proposal = state.proposal {
            if proposal.content.origin == .localArithmetic { return "Calculated from your notes" }
            var seen = Set<String>()
            let titles = proposal.usedCitations.compactMap { seen.insert($0.passage.documentID).inserted ? $0.passage.title : nil }
            return titles.isEmpty ? "Autofill ready" : "Autofilled from " + titles.joined(separator: ", ")
        }
        if state.processing {
            guard let gap = state.missingInformation else { return "Thinking…" }
            let target = gap.subjects?.map(\.quote).joined(separator: " and ")
                ?? (gap.targets.count == 1 ? GapHeadingRequest.inspect(gap.targets[0].quote)?.subject : nil)
                ?? gap.targets.map(\.quote).joined(separator: " and ")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
            let verb: String
            switch gap.operation {
            case .define: verb = "Defining"
            case .giveExample: verb = "Illustrating"
            case .compare: verb = "Comparing"
            case .explain: verb = "Explaining"
            case .continueThought: verb = "Completing"
            case .calculate: verb = "Calculating"
            }
            return target.isEmpty ? "Thinking…" : "\(verb) \(String(target.prefix(90)))…"
        }
        return state.clarification.isEmpty ? "Couldn’t autofill this yet" : "A little more detail?"
    }

    private var finishedMessage: String {
        if let issue = state.issue { return issue }
        if !state.clarification.isEmpty { return state.clarification }
        if !state.draftDetail.isEmpty { return state.draftDetail }
        if !state.sourceDetail.isEmpty { return state.sourceDetail }
        return "Try circling an unfinished heading or question."
    }

    private var acceptance: some View {
        VStack(alignment: .leading, spacing: 10) {
            if detailed {
                Text(state.insertion.handwritingDetail)
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("autofillHandwritingSource")
            }
            HStack(spacing: 12) {
                Button(action: state.decline) { Text("Decline").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.plain).bukoGlass(interactive: true).accessibilityIdentifier("declineAutofill")
                    .accessibilityHint("Removes the preview without changing your note.")
                Button(action: state.insertion.accept) {
                    HStack {
                        if state.insertion.isAccepting { ProgressView().controlSize(.small) }
                        Text("Accept")
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).bukoGlass(interactive: true)
                    .disabled(state.processing || !state.insertion.canAccept).accessibilityIdentifier("acceptAutofill")
                    .accessibilityHint("Inserts the green handwriting. Undo restores the original note and spacing.")
            }
        }
    }

    private func sources(_ citations: [LectureCitation], title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(citations) { citation in source(citation.passage, quote: citation.quote) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("autofillSources")
    }

    private func source(_ passage: LecturePassage, quote: String, prefix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                sourceTask?.cancel(); sourceError = nil
                sourceTask = Task {
                    guard let noteID = state.noteID else { return }
                    do {
                        let url = try await LectureLibrary.shared.pdfURL(noteID: noteID, documentID: passage.documentID)
                        try Task.checkCancellation()
                        sourcePreview = LecturePDFDestination(url: url, page: passage.page, quote: quote, title: passage.title)
                    } catch is CancellationError { }
                    catch { sourceError = error.localizedDescription }
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(prefix)\(passage.title) – p. \(passage.page)", systemImage: "doc.text")
                        .font(.caption.weight(.semibold)).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    if let noteID = state.noteID {
                        LectureSourceThumbnail(noteID: noteID, passage: passage, quote: quote)
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier("autofillSourceLink")
            Text(quote).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("autofillSourcePassage")
            if passage.usedOCR { Text("Scanned page · OCR text").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

private struct DetailedAutofillPreview: View {
    let state: CircleIntentState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pipeline").font(.subheadline.weight(.semibold))
                ForEach(state.pipeline.steps) { step in PipelineStepView(step: step) }
                if state.proposal != nil {
                    Label("Handwriting preview ready", systemImage: "checkmark.circle.fill")
                        .font(.caption).accessibilityIdentifier("handwritingPipelineStage")
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("autofillPipeline")
            field("Inferred intent", state.intent, id: "inferredIntent")
            field("Proposed action", state.action, id: "proposedAction")
            if let gap = state.missingInformation {
                field("Missing information", gap.targets.map(\.quote).joined(separator: " · ") + "\n" + gap.informationNeeds.joined(separator: " · "), id: "missingInformationPlan")
                if !gap.alreadyCovered.isEmpty { field("Already written", gap.alreadyCovered.map(\.quote).joined(separator: "\n")) }
            }
            if let proposal = state.proposal { field("Proposed fill", proposal.text, id: "proposedContent") }
            if !state.draftDetail.isEmpty { field("Draft result", state.draftDetail) }
            if !state.clarification.isEmpty { field("Clarification", state.clarification, id: "intentClarification") }
            if let issue = state.issue { field("Couldn’t finish", issue, id: "intentIssue") }
            field("Evidence for intent", state.evidence)
            field("Source review", state.sourceDetail.isEmpty ? state.sourceLabel : state.sourceDetail, id: "autofillSource")
            field("Recognized handwriting · \(state.recognitionMethod)", state.recognizedText, id: "recognizedHandwriting")
            field("Nearby handwriting used as context", state.nearbyContext, id: "nearbyHandwritingContext")
            Text("Recognition \(state.recognitionSeconds, specifier: "%.1f") s · Intent \(state.intentSeconds, specifier: "%.1f") s · Retrieval \(state.retrievalSeconds, specifier: "%.1f") s · Draft \(state.draftingSeconds, specifier: "%.1f") s")
                .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("modelTiming")
            if !state.retrievalMethod.isEmpty { Text(state.retrievalMethod).font(.caption2).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("detailedAutofillContent")
    }

    private func field(_ title: String, _ value: String, id: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(value.isEmpty ? (state.processing ? "Waiting…" : "None") : value)
                .font(.caption).textSelection(.enabled).accessibilityIdentifier(id)
        }
    }
}

private struct PipelineStepView: View {
    let step: PipelineStep
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if !step.summary.isEmpty { Text(step.summary).font(.caption).textSelection(.enabled) }
                Text(step.instructions == nil ? "Input" : "Prompt input").font(.caption.weight(.semibold))
                Text(step.input).font(.caption.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("pipelineInput.\(step.id)")
                if let instructions = step.instructions {
                    DisclosureGroup("Instructions") {
                        Text(instructions).font(.caption.monospaced()).textSelection(.enabled)
                    }.font(.caption)
                }
            }.padding(.vertical, 6)
        } label: {
            HStack(spacing: 8) {
                if step.status == .running { ProgressView().controlSize(.mini) }
                else { Image(systemName: step.status == .completed ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(.secondary) }
                Text(step.title).font(.caption.weight(.medium))
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pipelineStep.\(step.id)")
    }
}
