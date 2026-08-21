import AppKit
import Foundation
import Metal
import simd

/// Loads one tree's compiled artifacts and stands its renderer up exactly once,
/// whether the caller is the window, `--probe`, or a headless snapshot.
///
/// One instance per tree, created lazily on first access — the quant window's
/// artifacts are not decoded until that window is opened, so the second tree
/// costs the primary window's first paint nothing.
///
/// Failures are carried, not thrown: `GraphDocument.load()` produces readable
/// diagnostics (missing artifacts, version mismatch, layout gaps) and a developer
/// who forgot to run `ContentBuild` should be told that in the window, not shown
/// an empty one.
@MainActor
final class SceneStore {
    static let shared = SceneStore(tree: .math)
    static let quant = SceneStore(tree: .quant)

    let tree: TreeSpec

    private(set) var scene: GraphScene?
    private(set) var renderer: GraphRenderer?
    /// User state (§3.2). Absent only when the content itself failed to load —
    /// there is nothing to score against.
    private(set) var scores: ScoreStore?
    /// §5.2's problem bank. Always present; `isAvailable` is false when no
    /// artifact was compiled, and the app degrades to self-report rather than
    /// failing (see `ProblemDocument`).
    private(set) var problems: ProblemDocument = .missing
    /// §6.6's program. Always present; `isAuthored` is false when the tree has
    /// none, and the Program surface simply is not offered.
    private(set) var program: ProgramDocument = .missing
    /// §5.3's placement session, when one has been started.
    private(set) var placement: PlacementStore?
    private(set) var errorMessage: String?
    private(set) var timings = RenderTimings()

    /// Retrievability decays continuously (§4.1), so the map has to be repainted
    /// even when nothing happens. A minute is far finer than the ramp can show —
    /// stability is measured in days — and costs one fold of a small log.
    private var decayTick: Timer?
    private var intakeObserver: (any NSObjectProtocol)?
    private static let decayInterval: TimeInterval = 60

    private init(tree: TreeSpec) {
        self.tree = tree
        let directories = GraphDocument.searchDirectories(subdirectory: tree.subdirectory)
        var timings = RenderTimings()
        do {
            let loadStart = CFAbsoluteTimeGetCurrent()
            let document = try GraphDocument.load(from: directories)
            timings.documentLoadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000

            let buildStart = CFAbsoluteTimeGetCurrent()
            let scene = GraphScene(document: document, theme: ThemeStore.shared.theme)
            timings.sceneBuildMs = (CFAbsoluteTimeGetCurrent() - buildStart) * 1000
            self.scene = scene

            guard let device = MTLCreateSystemDefaultDevice() else { throw RendererError.noDevice }
            // The window does not exist yet, so the atlas is rasterised for the
            // main screen's backing scale. A window dragged to a display with a
            // different scale keeps working; its labels are merely resampled.
            let renderer = try GraphRenderer(
                device: device, scene: scene, timings: timings,
                backingScale: NSScreen.main?.backingScaleFactor ?? 2)
            self.renderer = renderer
            self.timings = renderer.timings

            // Built after the renderer so the first repaint has somewhere to land:
            // `ScoreStore.init` folds the log and fires `onChange` immediately, so
            // the very first frame is already wearing §4.5's colours rather than
            // flashing Phase 4's taxonomy palette and then correcting itself.
            // Decoded after the renderer is standing: the bank is not on the
            // first-paint path (D3.2 makes decode the dominant launch term), and
            // the map must be interactive before assessment is reachable.
            let problems = ProblemDocument.load(from: directories)
            self.problems = problems
            program = ProgramDocument.load(from: directories)

            let scores = ScoreStore(document: document, problems: problems.bank, tree: tree)
            scores.hueResolver = { scene.hue(of: $0) }
            self.scores = scores
            placement = PlacementStore(scores: scores, bank: problems.bank, tree: tree)
            scores.onChange = { [weak renderer] in
                guard let renderer else { return }
                renderer.applyScores(scores.visuals(for: document))
                // The view pauses itself once the reveal settles, so a colour
                // write is invisible until something asks for a frame.
                renderer.requestRedraw?()
            }
            renderer.applyScores(scores.visuals(for: document))
            startDecayTick(scores)
            startIntakeWatch(scores)
        } catch {
            self.timings = timings
            errorMessage = String(describing: error)
        }
    }

    /// A pinned clock (`MATHTREE_NOW`) means the scene is deliberately frozen for
    /// a snapshot or a determinism check; ticking would defeat the point.
    private func startDecayTick(_ scores: ScoreStore) {
        guard !scores.isClockPinned, !scores.isReadOnly else { return }
        decayTick = Timer.scheduledTimer(withTimeInterval: Self.decayInterval, repeats: true) { _ in
            Task { @MainActor in scores.evaluate() }
        }
    }

    /// §8.2's intake is drained once at launch (in `ScoreStore.init`) and again
    /// every time the app is activated. Activation rather than a poll because the
    /// directory fills while the app is *closed* — the moment the user brings the
    /// map forward is exactly when the queue is worth reading, and it costs one
    /// directory listing.
    private func startIntakeWatch(_ scores: ScoreStore) {
        guard !scores.isReadOnly, scores.intake != nil else { return }
        intakeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in scores.drainShifuIntake() }
        }
    }
}
