import SwiftUI

struct CircleIntentOverlay: View {
    let state: CircleIntentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if state.phase != .idle {
                    jelly(in: geometry.size)
                        .allowsHitTesting(false)
                    if state.phase == .finished || state.processing {
                        popup
                            .frame(width: min(340, geometry.size.width - 32))
                            .frame(maxHeight: min(360, geometry.size.height - 160))
                            .fixedSize(horizontal: false, vertical: true)
                            .background {
                                GeometryReader { card in
                                    Color.clear.onAppear { positionPopup(card.size, viewport: geometry.size) }
                                        .onChange(of: card.size) { _, size in positionPopup(size, viewport: geometry.size) }
                                        .onChange(of: state.selectionBounds) { _, _ in positionPopup(card.size, viewport: geometry.size) }
                                }
                            }
                            .offset(x: state.popupBounds.minX, y: state.popupBounds.minY)
                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.58), value: state.phase)
        }
        .ignoresSafeArea()
    }

    private func jelly(in viewport: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !state.processing || reduceMotion)) { timeline in
            let wave = reduceMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * 3.6)
            let shape = SelectionJellyShape(points: state.outline, boxes: state.textBounds)
            GlassEffectContainer(spacing: 12) {
                shape.fill(.clear)
                    .glassEffect(.clear, in: shape)
                    .glassEffectID("selection-jelly", in: glass)
                    .overlay {
                        shape.fill(.white.opacity(state.processing ? 0.06 + 0.04 * wave : 0.025))
                        shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.08), .cyan.opacity(0.55)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.4)
                            .opacity(state.processing ? 0.7 + 0.25 * wave : 0.75)
                    }
                    .phaseAnimator([false, true], trigger: state.phase) { content, expanded in
                        content.scaleEffect(x: reduceMotion ? 1 : (expanded ? 1.035 : 1),
                                            y: reduceMotion ? 1 : (expanded ? 0.96 : 1),
                                            anchor: UnitPoint(x: state.selectionBounds.midX / max(1, viewport.width),
                                                              y: state.selectionBounds.midY / max(1, viewport.height)))
                    } animation: { _ in reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.38) }
            }
        }
    }

    private var popup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if state.processing { ProgressView().controlSize(.small) }
                Text(state.phase == .recognizing ? "Reading handwriting…" : state.phase == .inferring ? "Interpreting intent…" : "Intent guess")
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: state.cancel) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss intent")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let issue = state.issue { Text(issue).font(.subheadline).accessibilityIdentifier("intentIssue") }
                    if !state.intent.isEmpty { Text(state.intent).font(.body).accessibilityIdentifier("intentGuess") }
                    if !state.clarification.isEmpty { Text(state.clarification).font(.subheadline).foregroundStyle(.secondary) }
                    if !state.recognizedText.isEmpty {
                        Text("Recognized handwriting · \(state.recognitionMethod)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(state.recognizedText).font(.subheadline).textSelection(.enabled)
                            .accessibilityIdentifier("recognizedHandwriting")
                    }
                    if !state.evidence.isEmpty { Text("Evidence: \(state.evidence)").font(.caption).foregroundStyle(.secondary) }
                    if !state.intent.isEmpty { Text("On-device · \(state.elapsed, specifier: "%.1f") s").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        // Regular native glass keeps diagnostic text readable over dense handwriting.
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .accessibilityIdentifier("intentPopup")
    }

    private func positionPopup(_ size: CGSize, viewport: CGSize) {
        let region = state.textBounds.reduce(state.selectionBounds) { $0.union($1) }
        let rightFits = region.maxX + 16 + size.width < viewport.width - 16
        let x = rightFits ? region.maxX + 16 : max(16, min(viewport.width - size.width - 16, region.minX))
        let preferredY = rightFits ? region.minY : region.maxY + 18
        let y = min(max(100, preferredY), max(100, viewport.height - size.height - 96))
        state.popupBounds = CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// Native glass follows the sampled gesture, then recognizer-derived word envelopes.
private struct SelectionJellyShape: Shape {
    let points: [CGPoint]
    let boxes: [CGRect]
    func path(in rect: CGRect) -> Path {
        if boxes.isEmpty { return Path(CircleGeometry.path(points)) }
        var path = Path()
        for box in boxes { path.addRoundedRect(in: box, cornerSize: CGSize(width: min(12, box.height / 2), height: min(12, box.height / 2))) }
        return path
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
