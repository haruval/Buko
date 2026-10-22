import SwiftUI

/// Shared native-glass tint for the circle AI interaction and its toolbar affordance.
enum CircleAIStyle {
    static let green = Color(red: 0.18, green: 0.88, blue: 0.38)
    static let glassTint = green.opacity(0.52)
}

struct CircleIntentOverlay: View {
    let state: CircleIntentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sourcePreview: LecturePDFDestination?
    @State private var sourceError: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if state.phase != .idle {
                    jelly(in: geometry.size)
                        .allowsHitTesting(false)
                    if state.phase == .finished || state.processing {
                        popup
                            .frame(width: state.popupBounds.isEmpty
                                   ? CirclePopupPlacement.preferredWidth(viewport: geometry.size, region: state.selectionBounds.applying(state.projection))
                                   : min(state.popupBounds.width, geometry.size.width - 32), height: min(600, geometry.size.height - 160))
                            .background {
                                GeometryReader { card in
                                    Color.clear.onAppear { positionPopup(card.size, viewport: geometry.size) }
                                        .onChange(of: card.size) { _, size in positionPopup(size, viewport: geometry.size) }
                                        .onChange(of: geometry.size) { _, _ in positionPopup(card.size, viewport: geometry.size) }
                                }
                            }
                            .offset(x: state.popupBounds.minX, y: state.popupBounds.minY)
                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .sheet(item: $sourcePreview) { LecturePDFView(destination: $0) }
    }

    private func jelly(in viewport: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                               paused: reduceMotion || (!state.processing && !state.motionActive))) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let wave = reduceMotion ? 0 : sin(now * 3.6)
            // Keep a single native-glass surface through tracing, inward fill,
            // and molding. No view replacement or implicit crossfade at recognition.
            let shape = GestureJellyShape(paint: state.paintedPath, tailAnchor: state.tailAnchor, droplet: state.droplet,
                release: state.release, projection: state.projection, boundary: state.closedBoundary, rectangle: state.fittedRectangle,
                closeAge: state.closedAt.map { now - $0 }, morphAge: state.morphBegan.map { now - $0 },
                now: now, reduceMotion: reduceMotion).path(in: CGRect(origin: .zero, size: viewport))
            glassSurface(shape, wave: wave)
                .frame(width: viewport.width, height: viewport.height)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }

    private func glassSurface<S: Shape>(_ shape: S, wave: Double) -> some View {
        shape.fill(.clear)
            // Clear is the most transparent public native-glass variant. The SDK
            // does not expose a per-view override for the system opacity slider.
            .glassEffect(.clear.tint(CircleAIStyle.glassTint), in: shape)
            .overlay {
                shape.fill(.white.opacity(state.processing ? 0.06 + 0.04 * wave : 0.025))
                shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.08), CircleAIStyle.green.opacity(0.65)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    .opacity(state.processing ? 0.7 + 0.25 * wave : 0.75)
            }
    }

    private var popup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Autofill preview").font(.headline)
                Spacer(minLength: 8)
                Button(action: state.cancel) {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss intent")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.processing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(state.progressLabel)
                                .font(.subheadline)
                        }
                    }
                    pipelineSection("1. Intent Guess", text: state.intent, identifier: "intentGuess")
                    pipelineSection("2. Action that should be taken", text: state.action, identifier: "intentAction")
                    if let gap = state.missingInformation {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Missing information").font(.subheadline.weight(.semibold))
                            Text(gap.informationNeeds.joined(separator: " · ")).font(.caption)
                            if !gap.alreadyCovered.isEmpty {
                                Text("Already written: " + gap.alreadyCovered.map(\.quote).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("missingInformationPlan")
                    }
                    proposedFill
                    if !state.clarification.isEmpty {
                        Text(state.clarification).font(.subheadline).accessibilityIdentifier("intentClarification")
                    }
                    if let issue = state.issue { Text(issue).font(.subheadline).accessibilityIdentifier("intentIssue") }
                    VStack(alignment: .leading, spacing: 6) {
                        Label(state.sourceLabel, systemImage: state.citations.isEmpty ? "info.circle" : "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("autofillSource")
                        if !state.sourceDetail.isEmpty { Text(state.sourceDetail).font(.caption).foregroundStyle(.secondary) }
                    }
                    if !state.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Lecture sources").font(.subheadline.weight(.semibold))
                            ForEach(Array(state.citations.enumerated()), id: \.offset) { index, citation in
                                VStack(alignment: .leading, spacing: 6) {
                                    Button {
                                        Task {
                                            guard let noteID = state.noteID else { return }
                                            do {
                                                let url = try await LectureLibrary.shared.pdfURL(noteID: noteID, documentID: citation.passage.documentID)
                                                sourcePreview = LecturePDFDestination(url: url, page: citation.passage.page, quote: citation.quote)
                                            } catch { sourceError = error.localizedDescription }
                                        }
                                    } label: {
                                        Label("[\(index + 1)] \(citation.passage.title) · p. \(citation.passage.page)", systemImage: "arrow.up.right.square")
                                            .font(.caption.weight(.semibold)).multilineTextAlignment(.leading)
                                    }
                                    Text("“\(citation.quote)”").font(.caption).textSelection(.enabled)
                                    if citation.passage.usedOCR { Text("Scanned page · OCR quotation").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                            if let sourceError { Text(sourceError).font(.caption).foregroundStyle(.red) }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        if state.arithmeticChecked { Text("Matrix arithmetic checked locally").font(.caption.weight(.semibold)) }
                        Text("Evidence").font(.caption.weight(.semibold))
                        Text(state.evidence.isEmpty ? "Not available yet." : state.evidence).font(.caption)
                        Text("Nearby handwriting used as context").font(.caption.weight(.semibold))
                        Text(state.nearbyContext.isEmpty
                             ? (state.phase == .recognizing ? "Reading nearby handwriting…" : "No nearby handwriting recognized.")
                             : state.nearbyContext)
                            .font(.caption).textSelection(.enabled).accessibilityIdentifier("nearbyHandwritingContext")
                        Text("Recognized handwriting · \(state.recognitionMethod)").font(.caption.weight(.semibold))
                        Text(state.recognizedText.isEmpty ? "Not available yet." : state.recognizedText)
                            .font(.subheadline).textSelection(.enabled).accessibilityIdentifier("recognizedHandwriting")
                        Text("On-device model · \(state.elapsed, specifier: "%.1f") s")
                            .font(.caption).accessibilityIdentifier("modelTiming")
                        Text("Missing-information retrieval")
                            .font(.caption2)
                        Text("Intent \(state.intentSeconds, specifier: "%.1f") s · Evidence \(max(0, state.proposalSeconds - state.draftingSeconds), specifier: "%.1f") s · Draft \(state.draftingSeconds, specifier: "%.1f") s · Recognition \(state.recognitionSeconds, specifier: "%.1f") s")
                            .font(.caption2)
                        if !state.retrievalMethod.isEmpty {
                            Text("Retrieval \(state.retrievalSeconds, specifier: "%.2f") s · \(state.retrievedPassageCount) passages · \(state.retrievalMethod)")
                                .font(.caption2).accessibilityIdentifier("retrievalTiming")
                        }
                    }
                    .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(action: state.cancel) {
                Text("okay")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .bukoGlass(interactive: true)
            .accessibilityIdentifier("acknowledgeAutofill")
            .accessibilityHint("Closes the preview. Your note is unchanged.")
        }
        .padding(16)
        .glassEffect(.regular.tint(CircleAIStyle.green.opacity(0.28)), in: .rect(cornerRadius: 26))
        .accessibilityIdentifier("intentPopup")
    }

    private var proposedFill: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3. Proposed fill").font(.subheadline.weight(.semibold))
            if let proposal = state.proposal {
                ForEach(Array(proposal.content.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            if !line.citationIndices.isEmpty {
                                Text(line.citationIndices.map { "[\($0 + 1)]" }.joined(separator: " "))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel("Lecture sources " + line.citationIndices.map { String($0 + 1) }.joined(separator: ", "))
                            }
                        }
                    }
                }
                .accessibilityIdentifier("proposedContent")
                Text(state.draftDetail).font(.caption).foregroundStyle(.secondary)
                Text("Preview only · Nothing has been added to your note.")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("autofillPreviewOnly")
            } else {
                Text(state.processing ? (state.phase == .drafting ? "Drafting the missing text…" : "Waiting for the proposed fill…")
                     : state.draftDetail.isEmpty ? "No proposed fill available." : state.draftDetail)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("proposedFillStatus")
            }
        }
    }

    private func pipelineSection(_ title: String, text: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text.isEmpty ? (state.processing ? "Waiting…" : "Not available.") : text)
                .font(.body).textSelection(.enabled).accessibilityIdentifier(identifier)
        }
    }

    private func positionPopup(_ size: CGSize, viewport: CGSize) {
        state.positionPopup(size: size, viewport: viewport)
    }
}

/// One persistent material boundary, driven by explicit geometry/physics.
private struct GestureJellyShape: Shape {
    let paint: CGPath
    let tailAnchor: CGPoint?
    let droplet: CircleDropletDynamics?
    let release: CircleJellyGeometry.Release?
    let projection: CGAffineTransform
    let boundary: CircleJellyGeometry.Boundary?
    let rectangle: CircleJellyGeometry.Boundary?
    let closeAge: TimeInterval?
    let morphAge: TimeInterval?
    let now: TimeInterval
    let reduceMotion: Bool

    func path(in rect: CGRect) -> Path {
        materialPath().applying(projection)
    }

    private func materialPath() -> Path {
        if let boundary, let closeAge {
            if let rectangle, let morphAge {
                return Path(CircleJellyGeometry.smoothPath(CircleJellyGeometry.moldedContour(
                    from: boundary, to: rectangle, age: morphAge, reduceMotion: reduceMotion)))
            }
            if let release { return Path(release.path(age: closeAge, reduceMotion: reduceMotion)) }
            return Path(CircleJellyGeometry.inwardFill(boundary, age: closeAge, reduceMotion: reduceMotion))
        }
        guard let droplet else { return Path() }
        let blob = CircleJellyGeometry.smoothPath(droplet.contour(at: now, reduceMotion: reduceMotion))
        let head = reduceMotion ? droplet.target : droplet.sample(at: now).position
        let tip = tailAnchor.map { CircleJellyGeometry.paint([$0, head]) } ?? CGMutablePath()
        return Path(paint.union(tip).union(blob))
    }
}

/// The full-screen SwiftUI host must pass all non-popup touches through to PencilKit.
final class CircleOverlayContainer: UIView {
    weak var state: CircleIntentState?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let state, state.phase != .idle else { return false }
        return state.popupBounds.contains(point)
    }
}
