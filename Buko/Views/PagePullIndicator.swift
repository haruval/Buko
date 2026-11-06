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

                        let diameter: CGFloat = 20 + min(1, state.progress) * 6
                        let frame = CGRect(
                            x: state.indicatorCenter.x - diameter / 2,
                            y: state.indicatorCenter.y + 5 + min(1, state.progress) * 45,
                            width: diameter, height: diameter)
                        Color.clear
                            .frame(width: max(1, frame.width), height: max(1, frame.height))
                            .bukoGlass(cornerRadius: diameter / 2)
                            .glassEffectID("pull-drop", in: glass)
                            .position(x: frame.midX, y: frame.midY)
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
