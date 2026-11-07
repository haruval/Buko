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
}

/// Anchored in document space below the final sheet. Native glass joins the dot
/// to the pill, then separates it as the append detent approaches.
struct PagePullIndicator: View {
    let state: PagePullState
    @Namespace private var glass

    var body: some View {
        GeometryReader { _ in
            if state.indicatorVisible && !state.isTurning {
                GlassEffectContainer(spacing: 22) {
                    ZStack(alignment: .topLeading) {
                        Text(state.progress >= 1 ? "Release to create page" : "Scroll to create page")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .bukoGlass(cornerRadius: 22)
                            .glassEffectID("pull-label", in: glass)
                            .position(state.indicatorCenter)
                            .transition(.identity)

                        if state.progress > 0 {
                            let pull = min(1, state.progress)
                            let diameter = 26 * sqrt(pull)
                            Color.clear
                                .frame(width: diameter, height: diameter)
                                .glassEffect(.clear, in: .circle)
                                .glassEffectID("pull-drop", in: glass)
                                .position(x: state.indicatorCenter.x,
                                          y: state.indicatorCenter.y + 20 + 43 * pull)
                        }
                    }
                }
                .environment(\.colorScheme, .dark)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.progress >= 1 ? "Release to create page" : "Scroll to create page")
            }
        }
        .allowsHitTesting(false)
    }
}
