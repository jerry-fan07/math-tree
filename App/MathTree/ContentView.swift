import GraphCore
import SwiftUI

struct ContentView: View {
    @State private var selection: NodeID?
    /// Open by default: §5.4's review surfacing is the loop the product is *for*,
    /// so it should not be behind a discovery step.
    @State private var isSidebarVisible = true
    /// §6.2's focus mode. Non-nil while the learning view covers the map; the
    /// camera it should fly back to is captured at entry, so leaving focus is a
    /// return to the place the user actually left (continuity of place).
    @State private var focus: FocusTarget?

    struct FocusTarget {
        var goal: NodeID
        var returnCamera: Camera
    }

    var body: some View {
        ZStack {
            Color(
                red: Palette.background.x, green: Palette.background.y, blue: Palette.background.z
            )
            .ignoresSafeArea()

            if let renderer = SceneStore.shared.renderer, let scene = SceneStore.shared.scene {
                GraphMetalView(
                    renderer: renderer, selection: $selection,
                    onToggleSidebar: { isSidebarVisible.toggle() },
                    onEscape: { escape() },
                    isNavigationSuspended: focus != nil
                )
                .ignoresSafeArea()
                .overlay(alignment: .bottomLeading) { hint }
                .overlay(alignment: .leading) { sidebar(scene: scene, renderer: renderer) }
                .overlay { focusOverlay(scene: scene, renderer: renderer) }
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

    // MARK: - Focus mode

    /// Enter (or retarget) focus mode. The return camera is captured once, on
    /// first entry: focusing deeper from inside focus mode must not overwrite
    /// where "Full map" goes back to.
    private func enterFocus(_ goal: NodeID, renderer: GraphRenderer) {
        guard let target = renderer.focusCamera(on: goal) else { return }
        let returnCamera = focus?.returnCamera ?? renderer.camera
        renderer.flyCamera(to: target)
        selection = nil
        withAnimation(.easeInOut(duration: 0.45)) {
            focus = FocusTarget(goal: goal, returnCamera: returnCamera)
        }
    }

    private func exitFocus(renderer: GraphRenderer) {
        guard let focus else { return }
        renderer.flyCamera(to: focus.returnCamera)
        withAnimation(.easeInOut(duration: 0.45)) { self.focus = nil }
    }

    /// Escape closes the topmost thing: the node panel first, then focus mode.
    private func escape() {
        if selection != nil {
            selection = nil
        } else if focus != nil, let renderer = SceneStore.shared.renderer {
            exitFocus(renderer: renderer)
        }
    }

    @ViewBuilder
    private func focusOverlay(scene: GraphScene, renderer: GraphRenderer) -> some View {
        if let focus, let scores = SceneStore.shared.scores {
            FocusView(
                goal: focus.goal,
                document: scene.document,
                scores: scores,
                onSelect: { id in selection = id },
                onExit: { exitFocus(renderer: renderer) }
            )
            .transition(.opacity)
        }
    }

    /// The review queue and the frontier (§5.4, §4.5). Absent when there is no
    /// user state to show — the map is still fully usable without it — and while
    /// focus mode owns the screen.
    @ViewBuilder
    private func sidebar(scene: GraphScene, renderer: GraphRenderer) -> some View {
        if isSidebarVisible, focus == nil, let scores = SceneStore.shared.scores {
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

    /// The node panel: Phase 4's contract plus Phase 6's scores and Phase 7's
    /// "learn this" action (§6.1 names it as part of the panel). In focus mode it
    /// overlays the focus view, so a syllabus entry can be read and reported
    /// without leaving the syllabus.
    private func panel(for node: Node, renderer: GraphRenderer) -> some View {
        NodePanel(
            node: node,
            document: renderer.scene.document,
            scores: SceneStore.shared.scores,
            onSelect: { id in
                selection = id
                if focus == nil { renderer.center(on: id) }
            },
            onClose: { selection = nil },
            onFocus: SceneStore.shared.scores == nil
                ? nil
                : { id in enterFocus(id, renderer: renderer) }
        )
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
        .transition(.move(edge: .trailing))
    }

    /// Map-mode hint only: the focus overlay covers it and carries its own
    /// "esc to go back" in the breadcrumb.
    private var hint: some View {
        Text(
            "scroll to pan · pinch or ⌘-scroll to zoom · click a node · esc to close · f to fit · r for review"
        )
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(.white.opacity(0.28))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Clears the sidebar rather than hiding behind it.
            .padding(
                .leading,
                isSidebarVisible && focus == nil && SceneStore.shared.scores != nil ? 268 : 0
            )
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
