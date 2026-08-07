import GraphCore
import SwiftUI

struct ContentView: View {
    @State private var selection: NodeID?
    /// Open by default: §5.4's review surfacing is the loop the product is *for*,
    /// so it should not be behind a discovery step.
    @State private var isSidebarVisible = true

    var body: some View {
        ZStack {
            Color(
                red: Palette.background.x, green: Palette.background.y, blue: Palette.background.z
            )
            .ignoresSafeArea()

            if let renderer = SceneStore.shared.renderer, let scene = SceneStore.shared.scene {
                GraphMetalView(
                    renderer: renderer, selection: $selection,
                    onToggleSidebar: { isSidebarVisible.toggle() }
                )
                .ignoresSafeArea()
                .overlay(alignment: .bottomLeading) { hint }
                .overlay(alignment: .leading) { sidebar(scene: scene, renderer: renderer) }
                .overlay(alignment: .trailing) {
                    if let selection, let index = scene.document.index(of: selection) {
                        panel(for: scene.document[index], renderer: renderer)
                    }
                }
            } else {
                LoadFailureView(message: SceneStore.shared.errorMessage ?? "Unknown load failure.")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    /// The review queue and the frontier (§5.4, §4.5). Absent when there is no
    /// user state to show — the map is still fully usable without it.
    @ViewBuilder
    private func sidebar(scene: GraphScene, renderer: GraphRenderer) -> some View {
        if isSidebarVisible, let scores = SceneStore.shared.scores {
            ReviewSidebar(
                document: scene.document,
                scores: scores,
                onSelect: { id in
                    selection = id
                    renderer.center(on: id)
                },
                onClose: { isSidebarVisible = false }
            )
            .frame(width: 268)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            }
            .transition(.move(edge: .leading))
        }
    }

    /// The node panel is Phase 4's other half and lives behind a fixed contract
    /// (`NodePanel(node:document:onSelect:onClose:)`); this view owns only the
    /// chrome it sits in and the selection state it reports back through.
    private func panel(for node: Node, renderer: GraphRenderer) -> some View {
        NodePanel(
            node: node,
            document: renderer.scene.document,
            scores: SceneStore.shared.scores,
            onSelect: { id in
                selection = id
                renderer.center(on: id)
            },
            onClose: { selection = nil }
        )
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
        .transition(.move(edge: .trailing))
    }

    private var hint: some View {
        Text(
            "scroll to pan · pinch or ⌘-scroll to zoom · click a node · esc to close · f to fit · r for review"
        )
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(.white.opacity(0.28))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Clears the sidebar rather than hiding behind it.
            .padding(.leading, isSidebarVisible && SceneStore.shared.scores != nil ? 268 : 0)
            .allowsHitTesting(false)
    }
}

/// `GraphDocument.load()` throws readable diagnostics; this shows them instead of
/// an empty window, so a developer who forgot to run `ContentBuild` is told so.
struct LoadFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Knowledge Tree could not load its content.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(message)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: 720, alignment: .leading)
    }
}

#Preview {
    ContentView()
}
