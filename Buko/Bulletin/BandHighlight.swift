import Observation
import SwiftUI

@Observable
final class BandHighlightState {
    var rect: CGRect?
}

struct BandHighlight: View {
    let state: BandHighlightState
    var body: some View {
        GeometryReader { _ in
            if let rect = state.rect, rect.width > 0, rect.height > 0 {
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .glassEffect(.clear.tint(.accentColor.opacity(0.18)), in: .rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1) }
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
