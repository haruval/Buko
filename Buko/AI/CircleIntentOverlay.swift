import SwiftUI

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
                               paused: reduceMotion || (!state.processing && state.phase != .tracing))) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let wave = reduceMotion ? 0 : sin(now * 3.6)
            // Word glass has its own identity and a fixed viewport. It never
            // inherits the tracing spring, popup layout, or a vertical transition.
            if !state.textBounds.isEmpty {
                let shape = WordJellyShape(boxes: state.textBounds)
                glassSurface(shape, wave: wave)
                    .frame(width: viewport.width, height: viewport.height)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
            } else if let origin = state.flowOrigin {
                let shape = CircleFlowShape(points: state.outline, times: state.pointTimes,
                    origin: origin, now: now, releasedAt: state.releasedAt, reduceMotion: reduceMotion)
                glassSurface(shape, wave: wave)
                    .frame(width: viewport.width, height: viewport.height)
            }
        }
    }

    private func glassSurface<S: Shape>(_ shape: S, wave: Double) -> some View {
        shape.fill(.clear)
            .glassEffect(.clear, in: shape)
            .overlay {
                shape.fill(.white.opacity(state.processing ? 0.06 + 0.04 * wave : 0.025))
                shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.08), .cyan.opacity(0.55)],
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

/// Ordered contour samples carry their arrival times: the radial spring front
/// follows clockwise/counterclockwise input naturally, rather than filling a chord.
private struct CircleFlowShape: Shape {
    let points: [CGPoint]
    let times: [TimeInterval]
    let origin: CGPoint
    let now: TimeInterval
    let releasedAt: TimeInterval?
    let reduceMotion: Bool

    func path(in rect: CGRect) -> Path {
        guard points.count >= 3, let first = points.first else { return Path() }
        let contour = points.enumerated().map { index, point -> CGPoint in
            let age = now - (index < times.count ? times[index] : now)
            let growth = reduceMotion ? 1 : CircleGeometry.springGrowth(age: age)
            return CGPoint(x: origin.x + (point.x - origin.x) * growth,
                           y: origin.y + (point.y - origin.y) * growth)
        }
        if let releasedAt, reduceMotion || now - releasedAt > 0.75 {
            return smoothed(contour)
        }
        // Collapse the two radial edges into the start point as the loop closes.
        let closing = releasedAt.map { reduceMotion ? 1 : min(1, max(0, (now - $0) / 0.55)) } ?? 0
        let hub = CGPoint(x: origin.x + (first.x - origin.x) * closing,
                          y: origin.y + (first.y - origin.y) * closing)
        return smoothed([hub] + contour)
    }

    private func smoothed(_ points: [CGPoint]) -> Path {
        guard points.count > 2 else { return Path() }
        var path = Path()
        let first = points[0], last = points[points.count - 1]
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for index in points.indices {
            let point = points[index], next = points[(index + 1) % points.count]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct WordJellyShape: Shape {
    let boxes: [CGRect]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for box in boxes {
            path.addRoundedRect(in: box, cornerSize: CGSize(width: 14, height: 14))
        }
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
