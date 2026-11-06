import SwiftUI

/// Shared native-glass tint for the circle AI interaction and its toolbar affordance.
enum CircleAIStyle {
    static let green = Color(red: 0.18, green: 0.88, blue: 0.38)
    static let glassTint = green.opacity(0.52)
    // Matches the circle/reflow center spring: roughly 15 rad/s, damping 0.7.
    static let previewSpring = Animation.spring(response: 0.42, dampingFraction: 0.7)
}

/// The same native material for the processing jelly and its compact toolbar mark.
struct CircleGlassSurface<S: Shape>: View {
    let shape: S
    var processing = false
    var wave = 0.0
    var interactive = false

    var body: some View {
        shape.fill(.clear)
            // Clear is the most transparent public native-glass variant.
            .glassEffect(.clear.tint(CircleAIStyle.glassTint).interactive(interactive), in: shape)
            .overlay {
                shape.fill(.white.opacity(processing ? 0.06 + 0.04 * wave : 0.025))
                shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.08), CircleAIStyle.green.opacity(0.65)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    .opacity(processing ? 0.7 + 0.25 * wave : 0.75)
            }
    }
}

struct CircleToolIcon: View {
    var body: some View {
        CircleGlassSurface(shape: RoundedRectangle(cornerRadius: 6, style: .continuous),
                           processing: true, interactive: true)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

struct CircleIntentOverlay: View {
    let state: CircleIntentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("detailedAutofillPreview") private var detailedPreview = false
    @State private var measuredHeight: CGFloat = 76
    @State private var dragOrigin: CGPoint?
    @State private var keyboardFrame = CGRect.null

    var body: some View {
        GeometryReader { geometry in
            let keyboardTop = keyboardFrame.isNull ? geometry.size.height
                : keyboardFrame.minY - geometry.frame(in: .global).minY
            let viewport = CGSize(width: geometry.size.width, height: min(geometry.size.height, max(240, keyboardTop)))
            let maximumHeight = max(120, min(620, viewport.height - 160))
            let popupSize = CGSize(
                width: min(detailedPreview ? 390 : 330, CirclePopupPlacement.preferredWidth(
                    viewport: geometry.size, region: state.selectionBounds.applying(state.projection))),
                height: min(measuredHeight, maximumHeight))
            let layout = PopupLayout(size: popupSize, viewport: viewport,
                insertedBounds: state.insertion.layout?.bounds, stage: AutofillPreviewStage(state), detailed: detailedPreview)
            ZStack(alignment: .topLeading) {
                if state.phase != .idle {
                    jelly(in: geometry.size)
                        .opacity(state.insertion.layout == nil ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.insertion.layout != nil)
                        .allowsHitTesting(false)
                    if state.phase == .finished || state.processing {
                        AutofillPreviewCard(state: state, detailed: detailedPreview, maximumHeight: maximumHeight, dragTitle: { translation in
                            if let translation {
                                if dragOrigin == nil { dragOrigin = state.popupHitBounds?.origin ?? state.popupBounds.origin }
                                guard let origin = dragOrigin else { return }
                                var transaction = Transaction(); transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    state.movePopup(to: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height), viewport: viewport)
                                }
                            } else { dragOrigin = nil }
                        }) { size in
                            guard state.phase != .idle, measuredHeight != size.height else { return }
                            measuredHeight = size.height
                            // Place from the measured destination immediately. A content
                            // measurement can arrive after the stage's layout change.
                            repositionPopup(CGSize(width: popupSize.width, height: min(size.height, maximumHeight)),
                                            viewport: viewport, animated: true)
                        }
                            .frame(width: popupSize.width, height: popupSize.height, alignment: .topLeading)
                            .transaction { $0.animation = nil }
                            .modifier(PopupPresentation(bounds: CGRect(origin: state.popupBounds.origin, size: popupSize), state: state))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("intentPopup")
                            .animation(stageAnimation, value: popupSize)
                            .onAppear { positionPopup(popupSize, viewport: viewport) }
                            .onChange(of: layout) { previous, current in
                                // Choose the destination once, never from intermediate spring sizes.
                                // Camera/viewport changes remain direct; only pipeline changes spring.
                                let animate = previous.viewport == current.viewport && previous.detailed == current.detailed
                                    && (previous.size != current.size || previous.stage != current.stage || previous.insertedBounds != current.insertedBounds)
                                repositionPopup(current.size, viewport: current.viewport, animated: animate)
                            }
                            .transition(reduceMotion ? .identity : .scale(scale: 0.75).combined(with: .opacity))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(name: "autofillOverlay")
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .null
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardFrame = .null }
        .onChange(of: state.phase) { _, phase in
            if phase == .idle { measuredHeight = 76; dragOrigin = nil }
        }
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
            CircleGlassSurface(shape: shape, processing: state.processing, wave: wave)
                .frame(width: viewport.width, height: viewport.height)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
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
        return content.clipShape(.rect(cornerRadius: CirclePopupPlacement.cornerRadius))
            .glassEffect(.regular.tint(CircleAIStyle.green.opacity(0.18)), in: .rect(cornerRadius: CirclePopupPlacement.cornerRadius))
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
                if reduceMotion || morphAge >= CircleJellyGeometry.morphDuration {
                    let width = rectangle.radii[0] * 2
                    let height = rectangle.radii[CircleJellyGeometry.sampleCount / 4] * 2
                    let rect = CGRect(x: rectangle.center.x - width / 2, y: rectangle.center.y - height / 2, width: width, height: height)
                    return Path(roundedRect: rect, cornerRadius: CirclePopupPlacement.cornerRadius / max(0.01, projection.a))
                }
                return Path(CircleJellyGeometry.smoothPath(CircleJellyGeometry.moldedContour(
                    from: boundary, to: rectangle, age: morphAge, reduceMotion: reduceMotion)))
            }
            if let release { return Path(release.path(age: closeAge, reduceMotion: reduceMotion)) }
            return Path(CircleJellyGeometry.inwardFill(boundary, age: closeAge, reduceMotion: reduceMotion))
        }
        guard let droplet else { return Path() }
        let blob = CircleJellyGeometry.smoothPath(droplet.contour(at: now, reduceMotion: reduceMotion))
        let head = droplet.target
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
