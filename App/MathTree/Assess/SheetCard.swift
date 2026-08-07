import SwiftUI

/// The card Phase 8's two modal surfaces are drawn on.
///
/// Exists for one reason that only became visible when the sheets were rendered
/// offscreen (D8.9): a `ScrollView` is greedy vertically, so a card built as
/// `ScrollView { … }.frame(maxHeight: 720)` is *always* 720 tall — a three-line
/// problem gets six hundred points of empty background under its buttons. The card
/// has to hug its content and only start scrolling once the content outgrows the
/// window.
///
/// So the content is measured and the scroll view is given `min(content, limit)`.
/// `onGeometryChange` is macOS 15, which is the deployment target (D0.2).
struct SheetCard<Content: View>: View {
    var width: CGFloat
    var maxHeight: CGFloat
    /// Drawn above the scrolling region, so a long problem scrolls under its own
    /// title rather than away from it.
    var header: AnyView?
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                header
                Rectangle().fill(PanelTheme.separator).frame(height: 1)
            }
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeight = $0
                    }
            }
            // `max` with a small floor so the card never collapses to nothing on
            // the first layout pass, before the measurement arrives.
            .frame(height: min(max(contentHeight, 40), maxHeight))
        }
        .frame(width: width)
        .background(PanelTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(PanelTheme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }
}
