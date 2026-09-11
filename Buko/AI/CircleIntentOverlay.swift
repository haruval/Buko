import SwiftUI

/// Shared native-glass tint for the circle AI interaction and its toolbar affordance.
enum CircleAIStyle {
    static let green = Color(red: 0.58, green: 0.85, blue: 0.63)
    static let glassTint = green.opacity(0.35)
}

struct CircleIntentOverlay: View {
    let state: CircleIntentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    private func jelly(in viewport: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                               paused: reduceMotion || (!state.processing && !state.motionActive))) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let wave = reduceMotion ? 0 : sin(now * 3.6)
            // Keep a single native-glass surface through tracing, inward fill,
            // and molding. No view replacement or implicit crossfade at recognition.
            let shape = GestureJellyShape(paint: state.paintedPath, tailAnchor: state.tailAnchor, droplet: state.droplet,
                boundary: state.closedBoundary, rectangle: state.fittedRectangle,
                closeAge: state.closedAt.map { now - $0 }, morphAge: state.morphBegan.map { now - $0 },
                now: now, reduceMotion: reduceMotion)
            glassSurface(shape, wave: wave)
                .frame(width: viewport.width, height: viewport.height)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }

    private func glassSurface<S: Shape>(_ shape: S, wave: Double) -> some View {
        shape.fill(.clear)
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
        .glassEffect(.regular.tint(CircleAIStyle.green.opacity(0.2)), in: .rect(cornerRadius: 26))
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

/// One persistent material boundary, driven by explicit geometry/physics.
private struct GestureJellyShape: Shape {
    let paint: CGPath
    let tailAnchor: CGPoint?
    let droplet: CircleDropletDynamics?
    let boundary: CircleJellyGeometry.Boundary?
    let rectangle: CircleJellyGeometry.Boundary?
    let closeAge: TimeInterval?
    let morphAge: TimeInterval?
    let now: TimeInterval
    let reduceMotion: Bool

    func path(in rect: CGRect) -> Path {
        if let boundary, let closeAge {
            if let rectangle, let morphAge {
                return Path(CircleJellyGeometry.smoothPath(CircleJellyGeometry.moldedContour(
                    from: boundary, to: rectangle, age: morphAge, reduceMotion: reduceMotion)))
            }
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
