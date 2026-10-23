import SwiftUI

/// Shared native-glass tint for the circle AI interaction and its toolbar affordance.
enum CircleAIStyle {
    static let green = Color(red: 0.18, green: 0.88, blue: 0.38)
    static let glassTint = green.opacity(0.52)
    // Matches the circle/reflow center spring: roughly 15 rad/s, damping 0.7.
    static let previewSpring = Animation.spring(response: 0.42, dampingFraction: 0.7)
}

struct CircleIntentOverlay: View {
    let state: CircleIntentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("detailedAutofillPreview") private var detailedPreview = false

    var body: some View {
        GeometryReader { geometry in
            let popupSize = CGSize(
                width: min(detailedPreview ? 390 : 330, CirclePopupPlacement.preferredWidth(
                    viewport: geometry.size, region: state.selectionBounds.applying(state.projection))),
                height: min(popupHeight, geometry.size.height - 160))
            let layout = PopupLayout(size: popupSize, viewport: geometry.size,
                insertedBounds: state.insertion.layout?.bounds, stage: AutofillPreviewStage(state), detailed: detailedPreview)
            ZStack(alignment: .topLeading) {
                if state.phase != .idle {
                    jelly(in: geometry.size)
                        .opacity(state.insertion.layout == nil ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.insertion.layout != nil)
                        .allowsHitTesting(false)
                    if state.phase == .finished || state.processing {
                        AutofillPreviewCard(state: state, detailed: detailedPreview)
                            .modifier(PopupPresentation(bounds: CGRect(origin: state.popupBounds.origin, size: popupSize), state: state))
                            .animation(stageAnimation, value: AutofillPreviewStage(state))
                            .onAppear { positionPopup(popupSize, viewport: geometry.size) }
                            .onChange(of: layout) { previous, current in
                                // Choose the destination once, never from intermediate spring sizes.
                                // Camera/viewport changes remain direct; only pipeline changes spring.
                                let animate = previous.viewport == current.viewport && previous.detailed == current.detailed
                                    && (previous.stage != current.stage || previous.insertedBounds != current.insertedBounds)
                                repositionPopup(popupSize, viewport: geometry.size, animated: animate)
                            }
                            .transition(reduceMotion ? .identity : .scale(scale: 0.75).combined(with: .opacity))
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

    private var popupHeight: CGFloat {
        if detailedPreview { return 620 }
        if let proposal = state.proposal { return proposal.usedCitations.isEmpty ? 220 : 390 }
        return state.processing ? (state.missingInformation == nil ? 132 : 164) : 250
    }

    private func positionPopup(_ size: CGSize, viewport: CGSize) {
        state.positionPopup(size: size, viewport: viewport)
    }

    private var stageAnimation: Animation? {
        detailedPreview || reduceMotion ? nil : CircleAIStyle.previewSpring
    }

    private func repositionPopup(_ size: CGSize, viewport: CGSize, animated: Bool) {
        withAnimation(animated ? stageAnimation : nil) {
            state.resetPopupAnchor()
            positionPopup(size, viewport: viewport)
        }
    }

    private struct PopupLayout: Equatable {
        let size: CGSize
        let viewport: CGSize
        let insertedBounds: CGRect?
        let stage: AutofillPreviewStage
        let detailed: Bool
    }
}

/// One interpolated rectangle drives both the visible frame and UIKit's pass-through
/// boundary. Geometry preferences describe the destination, not spring presentation.
private struct PopupPresentation: ViewModifier, Animatable {
    var bounds: CGRect
    let state: CircleIntentState

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(bounds.minX, bounds.minY), .init(bounds.width, bounds.height)) }
        set {
            bounds = CGRect(x: newValue.first.first, y: newValue.first.second,
                            width: newValue.second.first, height: newValue.second.second)
        }
    }

    func body(content: Content) -> some View {
        // This non-observed cache has no layout/state feedback. Updating it from
        // the interpolated value keeps moving controls from leaking taps to ink.
        state.popupHitBounds = bounds
        return content.frame(width: bounds.width, height: bounds.height)
            .offset(x: bounds.minX, y: bounds.minY)
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
        guard let state, state.hasPreview else { return false }
        return (state.popupHitBounds ?? state.popupBounds).contains(point)
    }
}
