import SwiftUI
import AVFoundation
import Observation

@Observable @MainActor
final class CubeState: NSObject {
    let microphone = CubeMicrophone()
    private(set) var visible = false
    private(set) var active = false
    private(set) var center = CGPoint.zero
    private(set) var scale: CGFloat = 1
    private(set) var appearance: CGFloat = 0
    private(set) var stretch: CGFloat = 0
    private(set) var tilt = CGVector.zero
    private(set) var facePull = CGVector.zero
    private(set) var voice: CGFloat = 0
    @ObservationIgnored private var dynamics = CubeDynamics(position: .zero)
    @ObservationIgnored private var notebookBounds = CGRect.zero
    @ObservationIgnored private var viewportHeight: CGFloat = 0
    @ObservationIgnored private var dragPoint: CGPoint?
    @ObservationIgnored var scrollWhileDragging: ((CGFloat) -> Void)?
    @ObservationIgnored private var offset = CGPoint.zero
    @ObservationIgnored private var dragOffset: CGVector?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var began: CFTimeInterval = 0
    @ObservationIgnored private var ending: CFTimeInterval?
    @ObservationIgnored private var lastTick: CFTimeInterval = 0

    var badgeVisible: Bool { active && (microphone.status == .denied || microphone.status == .unavailable) }
    var hitBounds: CGRect {
        guard active else { return .zero }
        let reach = CubeDynamics.edgeInset * scale
        return CGRect(x: center.x - reach, y: center.y - reach, width: 2 * reach, height: 2 * reach)
    }

    func spawn(bounds: CGRect, at point: CGPoint, scale: CGFloat, offset: CGPoint) {
        self.notebookBounds = bounds; self.scale = scale; self.offset = offset
        dynamics = CubeDynamics(position: CubeDynamics.clamp(point, to: bounds.insetBy(dx: CubeDynamics.edgeInset, dy: CubeDynamics.edgeInset)))
        active = true; visible = true; ending = nil; dragOffset = nil; dragPoint = nil
        facePull = .zero; tilt = .zero; stretch = 0; voice = 0
        began = CACurrentMediaTime(); appearance = UIAccessibility.isReduceMotionEnabled ? 1 : 0
        updateProjection(scale: scale, offset: offset)
        startClock()
        microphone.setActive(true)
    }

    func despawn() {
        guard active else { return }
        active = false; dragOffset = nil; dragPoint = nil; dynamics.target = nil
        microphone.setActive(false)
        ending = CACurrentMediaTime()
        if UIAccessibility.isReduceMotionEnabled { shutdown() }
    }

    func shutdown() {
        active = false; visible = false; dragOffset = nil; dragPoint = nil
        displayLink?.invalidate(); displayLink = nil
        microphone.setActive(false)
    }

    func foregroundChanged(_ foreground: Bool) {
        microphone.setForeground(foreground)
        if foreground, visible { startClock() }
        else { displayLink?.invalidate(); displayLink = nil; dynamics.target = nil; dragOffset = nil; dragPoint = nil }
    }

    func updateNotebook(bounds: CGRect, viewportHeight: CGFloat) {
        notebookBounds = bounds
        self.viewportHeight = viewportHeight
    }

    func updateProjection(scale: CGFloat, offset: CGPoint) {
        self.scale = scale; self.offset = offset
        center = CGPoint(x: dynamics.position.x * scale - offset.x, y: dynamics.position.y * scale - offset.y)
    }

    func drag(to point: CGPoint) {
        guard active else { return }
        dragPoint = point
        let location = CGPoint(x: (point.x + offset.x) / scale, y: (point.y + offset.y) / scale)
        if dragOffset == nil { dragOffset = CGVector(dx: dynamics.position.x - location.x, dy: dynamics.position.y - location.y) }
        dynamics.target = CGPoint(x: location.x + (dragOffset?.dx ?? 0), y: location.y + (dragOffset?.dy ?? 0))
    }

    func release() { dragOffset = nil; dragPoint = nil; dynamics.target = nil }

    func microphoneTapped() {
        if microphone.status == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        } else { microphone.startIfPossible() }
    }

    private func startClock() {
        guard displayLink == nil else { return }
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: CubeFrameTarget(self), selector: #selector(CubeFrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime(), reduce = UIAccessibility.isReduceMotionEnabled
        let dt = min(1.0 / 15, max(0, now - lastTick))
        lastTick = now
        if active, let dragPoint {
            let speed = CubeDynamics.edgeScrollSpeed(pointerY: dragPoint.y, viewportHeight: viewportHeight)
            if speed != 0 { scrollWhileDragging?(speed * CGFloat(dt)) }
            // Scrolling changes the document point under a stationary finger.
            drag(to: dragPoint)
        }
        dynamics.step(seconds: CGFloat(dt), bounds: notebookBounds, level: microphone.level, reduceMotion: reduce)
        if let ending {
            let t = min(1, (now - ending) / 0.22)
            appearance = CGFloat(pow(1 - t, 2))
            if t >= 1 { shutdown(); return }
        } else {
            let age = CGFloat(now - began)
            appearance = reduce || age >= 0.65 ? 1 : CircleJellyGeometry.spring(age, omega: 17, damping: 0.65)
        }
        voice = dynamics.voice
        stretch = reduce ? 0 : min(0.16, hypot(dynamics.velocity.dx, dynamics.velocity.dy) / 5000) + dynamics.collision * 0.12
        facePull = dynamics.facePull
        // Pulling up offsets the top upward, leaving the bottom wall exposed.
        // A small tilt adds perspective without moving the lower face ahead.
        tilt = CGVector(dx: facePull.dy * 0.35, dy: -facePull.dx * 0.35)
        updateProjection(scale: scale, offset: offset)
    }
}

private final class CubeFrameTarget: NSObject {
    weak var state: CubeState?
    init(_ state: CubeState) { self.state = state }
    @objc func tick(_ link: CADisplayLink) { state?.tick(link) }
}

struct CubeOverlay: View {
    let state: CubeState
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if state.visible {
                    cube
                        .scaleEffect(x: state.appearance * (1 + state.stretch) * (1 + state.voice * CubeDynamics.voiceScaleGain),
                                     y: state.appearance / (1 + state.stretch) * (1 + state.voice * CubeDynamics.voiceScaleGain))
                        .scaleEffect(state.scale)
                        .position(state.center)
                        .opacity(min(1, state.appearance * 3))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("cubeCanvas"))
                            .onChanged { state.drag(to: $0.location) }.onEnded { _ in state.release() })
                        .accessibilityLabel("Glass cube")
                        .accessibilityIdentifier("glassCube")
                        .accessibilityValue(state.microphone.status == .listening ? "Microphone listening" : "Microphone inactive")
                        .accessibilityHint("Drag between pages. Hold near the top or bottom to scroll the notebook.")
                    if state.badgeVisible {
                        Button(action: state.microphoneTapped) {
                            Image(systemName: "mic.slash.fill").font(.system(size: 12, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .position(x: state.center.x + 39 * state.scale, y: state.center.y + 39 * state.scale)
                        .accessibilityLabel(state.microphone.status == .denied ? "Microphone denied. Open Settings" : "Microphone unavailable. Retry")
                        .accessibilityIdentifier("cubeMicrophoneStatus")
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .coordinateSpace(name: "cubeCanvas")
            .transaction { $0.animation = nil }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in state.foregroundChanged(false) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in state.foregroundChanged(true) }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               AVAudioSession.InterruptionType(rawValue: raw) == .ended {
                state.microphone.startIfPossible()
            } else { state.microphone.interrupted() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if state.active, raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                || raw == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                state.microphone.interrupted(); state.microphone.startIfPossible()
            }
        }
    }

    private var cube: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack {
            // One consistently tinted glass surface spans the body and top.
            // Stacking a second tinted face would darken the cube while pulling.
            let wall = CubeSideWall(pull: state.facePull)
            wall.fill(.clear)
                .glassEffect(.clear.tint(CircleAIStyle.glassTint), in: wall)
                .overlay {
                    CubeConnectingEdges(pull: state.facePull)
                        .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                        .opacity(min(1, hypot(state.facePull.dx, state.facePull.dy) / 6))
                }
            // The moving face is defined by its rim rather than another glass layer.
            shape.fill(.clear)
                .overlay {
                    shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05), CircleAIStyle.green.opacity(0.75)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.3)
                }
                .rotation3DEffect(.degrees(state.tilt.dx), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(state.tilt.dy), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .offset(x: state.facePull.dx, y: state.facePull.dy)
            // Keep small native glass surfaces out of the face's 3D transform.
            // The eyes follow its translation, but remain upright during a pull.
            HStack(spacing: 10) {
                ForEach(0..<2) { _ in
                    Capsule().fill(.clear)
                        .frame(width: 12, height: 19)
                        .glassEffect(.clear.tint(.white.opacity(0.28)), in: .capsule)
                        .overlay {
                            Capsule().fill(LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay {
                            Capsule().stroke(LinearGradient(
                                colors: [.white.opacity(0.85), .white.opacity(0.08), .white.opacity(0.4)],
                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                        }
                }
            }
            .offset(x: state.facePull.dx, y: state.facePull.dy - 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: CubeDynamics.side, height: CubeDynamics.side)
        .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
        .contentShape(CubeSideWall(pull: state.facePull))
    }
}

final class CubeOverlayContainer: UIView {
    weak var state: CubeState?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        state?.hitBounds.contains(point) ?? false
    }
}

/// A rounded extrusion joining two translated faces, rather than two detached squares.
private struct CubeSideWall: Shape {
    let pull: CGVector
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let inset = rect.insetBy(dx: radius, dy: radius)
        let corners = [CGPoint(x: inset.minX, y: inset.minY), CGPoint(x: inset.maxX, y: inset.minY),
                       CGPoint(x: inset.maxX, y: inset.maxY), CGPoint(x: inset.minX, y: inset.maxY)]
        let points = (corners + corners.map { CGPoint(x: $0.x + pull.dx, y: $0.y + pull.dy) })
            .sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        func chain(_ points: [CGPoint]) -> [CGPoint] {
            var result: [CGPoint] = []
            for point in points {
                while result.count >= 2 && cross(result[result.count - 2], result[result.count - 1], point) <= 0 { result.removeLast() }
                result.append(point)
            }
            return result
        }
        let hull = Array(chain(points).dropLast()) + Array(chain(points.reversed()).dropLast())
        let core = CircleGeometry.path(hull)
        let rim = core.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 2)
        return Path(core.union(rim))
    }
}

/// Highlight the exposed rounded corner seams between the base and pulled face.
/// Trailing corners are visible; leading corners are hidden by the top face.
private struct CubeConnectingEdges: Shape {
    let pull: CGVector
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerInset: CGFloat = 18 * (1 - 1 / sqrt(2))
        for x: CGFloat in [-1, 1] {
            for y: CGFloat in [-1, 1] where x * pull.dx + y * pull.dy <= 0.01 {
                let base = CGPoint(x: rect.midX + x * (rect.width / 2 - cornerInset),
                                   y: rect.midY + y * (rect.height / 2 - cornerInset))
                path.move(to: base)
                path.addLine(to: CGPoint(x: base.x + pull.dx, y: base.y + pull.dy))
            }
        }
        return path
    }
}
