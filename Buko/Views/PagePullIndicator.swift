import Observation
import SwiftUI

@Observable
final class PagePullState {
    var progress: CGFloat = 0
    var pageIndex = 0
    var pageCount = 1
    var isTurning = false
    var didCreate = false
    var bottomOverBlack = false
    var topOverBlack = false
    var rightOverBlack = false
    var scrollProgress: CGFloat = 0
    var indicatorCenter = CGPoint.zero
    var indicatorVisible = false
    var birthFrame = CGRect.zero
    var creationProgress: CGFloat = 0
}

/// Anchored in document space below the final sheet. Native glass joins the dot
/// to the pill, then separates it as the append detent approaches.
struct PagePullIndicator: View {
    let state: PagePullState
    @Namespace private var glass

    var body: some View {
        GeometryReader { _ in
            if state.indicatorVisible || (state.isTurning && state.didCreate) {
                GlassEffectContainer(spacing: 22) {
                    ZStack(alignment: .topLeading) {
                        Text(state.isTurning ? "Page \(state.pageCount) created"
                             : state.progress >= 1 ? "Release to create page" : "Scroll to create page")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .bukoGlass(cornerRadius: 22)
                            .glassEffectID("pull-label", in: glass)
                            .opacity(state.isTurning ? max(0, 1 - state.creationProgress * 3) : 1)
                            .position(state.indicatorCenter)

                        let creating = state.isTurning && state.didCreate
                        let diameter: CGFloat = 20 + min(1, state.progress) * 6
                        let frame = creating ? state.birthFrame : CGRect(
                            x: state.indicatorCenter.x - diameter / 2,
                            y: state.indicatorCenter.y + 5 + min(1, state.progress) * 45,
                            width: diameter, height: diameter)
                        Color.clear
                            .frame(width: max(1, frame.width), height: max(1, frame.height))
                            .bukoGlass(cornerRadius: creating ? min(28, frame.width / 2) : diameter / 2)
                            .glassEffectID("pull-drop", in: glass)
                            .opacity(creating ? max(0, 1 - max(0, state.creationProgress - 0.55) / 0.45) : 1)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .environment(\.colorScheme, .dark)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.isTurning ? "New page created"
                                    : state.progress >= 1 ? "Release to create page" : "Scroll to create page")
            }
        }
        .allowsHitTesting(false)
    }
}
