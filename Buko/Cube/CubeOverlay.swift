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
    private(set) var voice: CGFloat = 0
    @ObservationIgnored private var dynamics = CubeDynamics(position: .zero)
    @ObservationIgnored private var page = CGRect.zero
    @ObservationIgnored private var offset = CGPoint.zero
    @ObservationIgnored private var dragOffset: CGVector?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var began: CFTimeInterval = 0
    @ObservationIgnored private var ending: CFTimeInterval?
    @ObservationIgnored private var lastTick: CFTimeInterval = 0

    var badgeVisible: Bool { active && (microphone.status == .denied || microphone.status == .unavailable) }
    var hitBounds: CGRect {
        guard active else { return .zero }
        return CGRect(x: center.x - 58 * scale, y: center.y - 58 * scale, width: 116 * scale, height: 116 * scale)
    }

    func spawn(page: CGRect, at point: CGPoint, scale: CGFloat, offset: CGPoint) {
        self.page = page; self.scale = scale; self.offset = offset
        dynamics = CubeDynamics(position: CubeDynamics.clamp(point, to: page.insetBy(dx: CubeDynamics.edgeInset, dy: CubeDynamics.edgeInset)))
        active = true; visible = true; ending = nil; dragOffset = nil
        began = CACurrentMediaTime(); appearance = UIAccessibility.isReduceMotionEnabled ? 1 : 0
        updateProjection(scale: scale, offset: offset)
        startClock()
        microphone.setActive(true)
    }

    func despawn() {
        guard active else { return }
        active = false; dragOffset = nil; dynamics.target = nil
        microphone.setActive(false)
        ending = CACurrentMediaTime()
        if UIAccessibility.isReduceMotionEnabled { shutdown() }
    }

    func shutdown() {
        active = false; visible = false; dragOffset = nil
        displayLink?.invalidate(); displayLink = nil
        microphone.setActive(false)
    }

    func foregroundChanged(_ foreground: Bool) {
        microphone.setForeground(foreground)
        if foreground, visible { startClock() }
        else { displayLink?.invalidate(); displayLink = nil; dynamics.target = nil; dragOffset = nil }
    }

    func updateProjection(scale: CGFloat, offset: CGPoint) {
        self.scale = scale; self.offset = offset
        center = CGPoint(x: dynamics.position.x * scale - offset.x, y: dynamics.position.y * scale - offset.y)
    }

    func drag(to point: CGPoint) {
        guard active else { return }
        let location = CGPoint(x: (point.x + offset.x) / scale, y: (point.y + offset.y) / scale)
        if dragOffset == nil { dragOffset = CGVector(dx: dynamics.position.x - location.x, dy: dynamics.position.y - location.y) }
        dynamics.target = CGPoint(x: location.x + (dragOffset?.dx ?? 0), y: location.y + (dragOffset?.dy ?? 0))
    }

    func release() { dragOffset = nil; dynamics.target = nil }

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
        dynamics.step(seconds: CGFloat(now - lastTick), page: page, level: microphone.level, reduceMotion: reduce)
        lastTick = now
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
        let targetTilt = CGVector(dx: reduce ? 0 : max(-18, min(18, dynamics.velocity.dy / 35)),
                                  dy: reduce ? 0 : max(-18, min(18, -dynamics.velocity.dx / 35)))
        tilt = CGVector(dx: tilt.dx + (targetTilt.dx - tilt.dx) * 0.2, dy: tilt.dy + (targetTilt.dy - tilt.dy) * 0.2)
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
                        .scaleEffect(x: state.appearance * (1 + state.stretch) * (1 + state.voice * 0.16),
                                     y: state.appearance / (1 + state.stretch) * (1 + state.voice * 0.16))
                        .scaleEffect(state.scale)
                        .position(state.center)
                        .opacity(min(1, state.appearance * 3))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("cubeCanvas"))
                            .onChanged { state.drag(to: $0.location) }.onEnded { _ in state.release() })
                        .accessibilityLabel("Glass cube")
                        .accessibilityIdentifier("glassCube")
                        .accessibilityValue(state.microphone.status == .listening ? "Microphone listening" : "Microphone inactive")
                        .accessibilityHint("Drag to move within this page.")
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
        let depth = min(12, hypot(state.tilt.dx, state.tilt.dy) * 0.45)
        return ZStack {
            // A rounded lower face exposes thickness only as the cube tilts.
            shape.fill(.clear)
                .glassEffect(.clear.tint(CircleAIStyle.green.opacity(0.65)), in: shape)
                .offset(x: -state.tilt.dy * 0.35, y: depth * 0.5 + state.tilt.dx * 0.2)
                .opacity(min(1, depth / 5))
            shape.fill(.clear)
                .glassEffect(.clear.tint(CircleAIStyle.glassTint), in: shape)
                .overlay {
                    shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05), CircleAIStyle.green.opacity(0.75)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.3)
                }
                .rotation3DEffect(.degrees(state.tilt.dx), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(state.tilt.dy), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        }
        .frame(width: CubeDynamics.side, height: CubeDynamics.side)
        .shadow(color: .black.opacity(0.14), radius: 3 + depth * 0.3, y: 2 + depth * 0.3)
        .contentShape(.rect(cornerRadius: 18))
    }
}

final class CubeOverlayContainer: UIView {
    weak var state: CubeState?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        state?.hitBounds.contains(point) ?? false
    }
}
