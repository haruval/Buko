import SwiftUI

enum WorkspaceChrome {
    // Additional room below the safe area for iPadOS window controls.
    static let topPadding: CGFloat = 44
}

extension View {
    func bukoGlass(cornerRadius: CGFloat = 28, interactive: Bool = false) -> some View {
        modifier(BukoGlass(cornerRadius: cornerRadius, interactive: interactive))
    }
}

private struct BukoGlass: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(
            .clear.interactive(interactive),
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}

/// Keep one glass surface alive while its bounds expand from the button's corner.
/// Both directions share the same geometry, so opening never slides in from offscreen.
struct ExpandingGlassPanel<Expanded: View, Compact: View>: View {
    let isExpanded: Bool
    let size: CGSize
    let alignment: Alignment
    let anchor: UnitPoint
    var compactSize = CGSize(width: 52, height: 52)
    @ViewBuilder var expanded: () -> Expanded
    @ViewBuilder var compact: () -> Compact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Fade content independently of the surface spring: spring opacity can
        // briefly reveal outgoing labels again while the panel settles.
        ZStack(alignment: alignment) {
            if isExpanded {
                expanded()
                    .frame(width: size.width, height: size.height)
                    .transition(.asymmetric(
                        insertion: (reduceMotion ? AnyTransition.opacity
                            : .scale(scale: 0.15, anchor: anchor).combined(with: .opacity))
                            .animation(.easeOut(duration: 0.18).delay(reduceMotion ? 0 : 0.06)),
                        removal: .opacity.animation(.linear(duration: 0.06))
                    ))
            } else {
                compact()
                    .frame(width: compactSize.width, height: compactSize.height)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.12).delay(reduceMotion ? 0 : 0.10)),
                        removal: .opacity.animation(.linear(duration: 0.05))
                    ))
            }
        }
        .frame(width: isExpanded ? size.width : compactSize.width, height: isExpanded ? size.height : compactSize.height, alignment: alignment)
        .clipShape(.rect(cornerRadius: isExpanded ? 32 : 26))
        .bukoGlass(cornerRadius: isExpanded ? 32 : 26)
    }
}

struct ShelfButton: View {
    let title: String
    let symbol: String
    var selected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(width: 46, height: 46)
                .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(title)
    }
}
