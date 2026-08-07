import GraphCore
import SwiftUI

struct ContentView: View {
    @State private var selection: NodeID?

    var body: some View {
        ZStack {
            Color(
                red: Palette.background.x, green: Palette.background.y, blue: Palette.background.z
            )
            .ignoresSafeArea()

            if let renderer = SceneStore.shared.renderer, let scene = SceneStore.shared.scene {
                GraphMetalView(renderer: renderer, selection: $selection)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottomLeading) { hint }
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

    /// The node panel is Phase 4's other half and lives behind a fixed contract
    /// (`NodePanel(node:document:onSelect:onClose:)`); this view owns only the
    /// chrome it sits in and the selection state it reports back through.
    private func panel(for node: Node, renderer: GraphRenderer) -> some View {
        NodePanel(
            node: node,
            document: renderer.scene.document,
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
        Text("scroll to pan · pinch or ⌘-scroll to zoom · click a node · esc to close · f to fit")
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(.white.opacity(0.28))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
