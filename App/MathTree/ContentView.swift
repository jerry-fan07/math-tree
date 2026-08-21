import GraphCore
import SwiftUI

struct ContentView: View {
    /// Which tree this window shows. Each window owns one store; nothing below
    /// this view reaches for a singleton, so the same view serves every tree.
    var store: SceneStore = .shared

    @State private var selection: NodeID?
    /// Open by default: §5.4's review surfacing is the loop the product is *for*,
    /// so it should not be behind a discovery step.
    @State private var isSidebarVisible = true
    /// §6.2's focus mode. Non-nil while the learning view covers the map; the
    /// camera it should fly back to is captured at entry, so leaving focus is a
    /// return to the place the user actually left (continuity of place).
    @State private var focus: FocusTarget?
    /// §5.2's problem sheet, when one is open.
    @State private var attempt: Attempt?
    /// §5.3's placement flow.
    @State private var isPlacing = false
    /// §6.6's program, when the tree has one and it is open.
    @State private var isProgramOpen = false
    /// The node the program should open at — the panel's "read the lesson" jump.
    @State private var programTarget: NodeID?
    /// The renderer's zoom band, pushed up when it changes. The map legends are
    /// drawn from mid zoom on, matching the design's frames.
    @State private var band: ZoomBand = .overview

    @Environment(\.colorScheme) private var systemAppearance

    struct FocusTarget {
        var goal: FocusGoal
        var returnCamera: Camera
    }

    /// A problem opened for review (not for placement — that flow owns its own).
    struct Attempt: Identifiable {
        var problem: Problem
        var subject: NodeID
        var id: String { problem.id.rawValue }
    }

    var body: some View {
        let theme = ThemeStore.shared.theme
        ZStack {
            theme.canvasEdge.color.ignoresSafeArea()

            if let renderer = store.renderer, let scene = store.scene {
                GraphMetalView(
                    renderer: renderer, selection: $selection,
                    onToggleSidebar: { isSidebarVisible.toggle() },
                    onEscape: { escape() },
                    isNavigationSuspended: focus != nil || isProgramOpen
                )
                .ignoresSafeArea()
                .overlay(alignment: .top) { commandBar(scene: scene, renderer: renderer) }
                .overlay(alignment: .bottom) { legends }
                .overlay(alignment: .topLeading) { sidebar(scene: scene, renderer: renderer) }
                // Under the panel on purpose: selecting a step opens the panel
                // *over* the reader, so a lesson and its node's history can be
                // read side by side without leaving the program.
                .overlay { programOverlay(scene: scene) }
                .overlay(alignment: .topTrailing) {
                    if let selection, let index = scene.document.index(of: selection) {
                        panel(for: scene.document[index], renderer: renderer)
                    }
                }
                .overlay { focusOverlay(scene: scene, renderer: renderer) }
                // Assessment sits above everything: a problem sheet and the
                // placement flow are modal by nature, and both are dismissible.
                .overlay { problemOverlay(scene: scene) }
                .overlay { placementOverlay(scene: scene, renderer: renderer) }
                .onAppear {
                    band = renderer.band
                    renderer.onBandChange = { band = $0 }
                }
            } else {
                LoadFailureView(message: store.errorMessage ?? "Unknown load failure.")
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        // The redesign is two directions of one design, and which one is showing
        // is the system's call — unless `MATHTREE_THEME` pinned it, which is how
        // the two frames are captured side by side.
        .onAppear { applyAppearance() }
        .onChange(of: systemAppearance) { applyAppearance() }
    }

    private func applyAppearance() {
        ThemeStore.shared.follow(systemAppearance)
        store.renderer?.setTheme(ThemeStore.shared.theme)
    }

    // MARK: - Chrome

    @ViewBuilder
    private func commandBar(scene: GraphScene, renderer: GraphRenderer) -> some View {
        if focus == nil, !isProgramOpen {
            CommandBar(
                document: scene.document,
                scores: store.scores,
                selection: selection,
                onSelect: { id in
                    selection = id
                    renderer.center(on: id)
                })
        }
    }

    /// The design puts both legends along the bottom of the map from mid zoom on.
    /// They clear the rail rather than hiding behind it, and step aside entirely
    /// for focus mode and the modal flows.
    @ViewBuilder
    private var legends: some View {
        let theme = ThemeStore.shared.theme
        if focus == nil, attempt == nil, !isPlacing, !isProgramOpen, band != .overview {
            HStack(alignment: .bottom) {
                EdgeLegend()
                Spacer(minLength: 24)
                ScoreScale()
            }
            .padding(.horizontal, theme.isDark ? 20 : 24)
            .padding(.bottom, theme.isDark ? 18 : 20)
            .padding(.leading, isRailVisible ? theme.railWidth : 0)
            .padding(.trailing, selection == nil ? 0 : theme.panelWidth)
            .transition(.opacity)
        }
    }

    // MARK: - Focus mode

    /// Enter (or retarget) focus mode. The return camera is captured once, on
    /// first entry: focusing deeper from inside focus mode must not overwrite
    /// where "Full map" goes back to.
    private func enterFocus(_ goal: FocusGoal, renderer: GraphRenderer) {
        guard let target = renderer.focusCamera(on: goal.id) else { return }
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

    /// Escape closes the topmost thing: the problem sheet, then placement, then the
    /// node panel, then the program, then focus mode — outermost-first, matching
    /// what covers what.
    private func escape() {
        if attempt != nil {
            attempt = nil
        } else if isPlacing {
            isPlacing = false
        } else if selection != nil {
            selection = nil
        } else if isProgramOpen {
            withAnimation(.easeInOut(duration: 0.3)) { isProgramOpen = false }
            programTarget = nil
        } else if focus != nil, let renderer = store.renderer {
            exitFocus(renderer: renderer)
        }
    }

    // MARK: - Assessment

    /// §5.4 routes review to a problem "whenever possible" and falls back to
    /// self-report otherwise — the panel and the sidebar both call this, so the
    /// routing lives in one place.
    private func review(_ id: NodeID) {
        guard let scores = store.scores, let problem = scores.nextProblem(for: id)
        else { return }
        attempt = Attempt(problem: problem, subject: id)
    }

    @ViewBuilder
    private func problemOverlay(scene: GraphScene) -> some View {
        if let attempt, let scores = store.scores, !isPlacing {
            ProblemSheet(
                problem: attempt.problem,
                subject: attempt.subject,
                document: scene.document,
                scores: scores,
                onGrade: { outcome, localized in
                    scores.record(outcome, on: attempt.problem, localizedTo: localized)
                    self.attempt = nil
                },
                // §5.4's micro-problem: instead of asserting where the gap is, ask
                // about it. The original miss is dropped without evidence — nothing
                // was localized, so there is nothing to record.
                onProbe: { problemID, node in
                    guard let followUp = scores.bank[problemID] else { return }
                    self.attempt = Attempt(problem: followUp, subject: node)
                },
                onDismiss: { self.attempt = nil }
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func placementOverlay(scene: GraphScene, renderer: GraphRenderer) -> some View {
        if isPlacing, let scores = store.scores,
            let placement = store.placement
        {
            PlacementView(
                document: scene.document,
                scores: scores,
                placement: placement,
                onSelect: { id in
                    isPlacing = false
                    selection = id
                    renderer.center(on: id)
                },
                onExit: { isPlacing = false }
            )
            .transition(.opacity)
        }
    }

    // MARK: - Program

    /// §6.6's reader, over the map the way focus mode is. Present only when the
    /// tree ships a program and there is user state to adapt it to.
    @ViewBuilder
    private func programOverlay(scene: GraphScene) -> some View {
        if isProgramOpen, let scores = store.scores, store.program.isAuthored {
            ProgramView(
                program: store.program.program,
                document: scene.document,
                scores: scores,
                target: programTarget,
                onSelect: { id in selection = id },
                onExit: {
                    withAnimation(.easeInOut(duration: 0.3)) { isProgramOpen = false }
                    programTarget = nil
                }
            )
            .transition(.opacity)
        }
    }

    private func openProgram(at target: NodeID? = nil) {
        programTarget = target
        selection = nil
        withAnimation(.easeInOut(duration: 0.3)) { isProgramOpen = true }
    }

    @ViewBuilder
    private func focusOverlay(scene: GraphScene, renderer: GraphRenderer) -> some View {
        if let focus, let scores = store.scores {
            FocusView(
                focus: focus.goal,
                document: scene.document,
                scores: scores,
                onSelect: { id in selection = id },
                onExit: { exitFocus(renderer: renderer) }
            )
            .transition(.opacity)
        }
    }

    private var isRailVisible: Bool {
        isSidebarVisible && focus == nil && !isProgramOpen && store.scores != nil
    }

    /// The review queue and the frontier (§5.4, §4.5). Absent when there is no
    /// user state to show — the map is still fully usable without it — and while
    /// focus mode owns the screen.
    ///
    /// A scrim under the command bar rather than a panel beside it: the redesign
    /// has the map run edge to edge and the rail fade out over it, so there is no
    /// border here and no material.
    @ViewBuilder
    private func sidebar(scene: GraphScene, renderer: GraphRenderer) -> some View {
        let theme = ThemeStore.shared.theme
        if isRailVisible, let scores = store.scores {
            ReviewSidebar(
                document: scene.document,
                scores: scores,
                placement: store.placement,
                onSelect: { id in
                    selection = id
                    renderer.center(on: id)
                },
                onReview: { review($0) },
                onPlace: { isPlacing = true },
                // §6.5's entry point that does not require finding a hub on the
                // map first: pick the subject by name, get the path.
                onLearnSubject: { enterFocus(.subject($0), renderer: renderer) },
                // §6.6's entry point: the program, resumable from the rail.
                program: store.program.isAuthored ? store.program.program : nil,
                onOpenProgram: store.program.isAuthored ? { openProgram() } : nil,
                onClose: { isSidebarVisible = false }
            )
            .frame(width: theme.railWidth)
            .padding(.top, theme.barHeight)
            .transition(.move(edge: .leading))
        }
    }

    /// The node panel: Phase 4's contract plus Phase 6's scores and Phase 7's
    /// "learn this" action (§6.1 names it as part of the panel). In focus mode it
    /// overlays the focus view, so a syllabus entry can be read and reported
    /// without leaving the syllabus.
    private func panel(for node: Node, renderer: GraphRenderer) -> some View {
        let theme = ThemeStore.shared.theme
        return NodePanel(
            node: node,
            document: renderer.scene.document,
            scores: store.scores,
            onSelect: { id in
                selection = id
                if focus == nil { renderer.center(on: id) }
            },
            onClose: { selection = nil },
            onFocus: store.scores == nil
                ? nil
                : { goal in enterFocus(goal, renderer: renderer) },
            onReview: { review($0) },
            // §6.6's connective tissue: any node on the map, straight to its
            // lesson in the program.
            onLesson: store.program.program.lesson(for: node.id) == nil
                ? nil
                : { id in openProgram(at: id) }
        )
        .frame(width: theme.panelWidth)
        .padding(.top, focus == nil ? theme.barHeight : 0)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.rule.color).frame(width: 1)
        }
        .transition(.move(edge: .trailing))
    }
}

/// `GraphDocument.load()` throws readable diagnostics; this shows them instead of
/// an empty window, so a developer who forgot to run `ContentBuild` is told so.
struct LoadFailureView: View {
    let message: String

    var body: some View {
        let theme = ThemeStore.shared.theme
        VStack(alignment: .leading, spacing: 14) {
            Text("Knowledge Tree could not load its content.")
                .font(Typeface.sans(17, .medium))
                .foregroundStyle(theme.ink.color)
            Text(message)
                .font(Typeface.mono(12))
                .foregroundStyle(theme.inkMuted.color)
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
