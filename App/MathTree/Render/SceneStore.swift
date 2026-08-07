import AppKit
import Foundation
import Metal
import simd

/// Loads the compiled artifacts and stands the renderer up exactly once, whether
/// the caller is the window, `--probe`, or a headless snapshot.
///
/// Failures are carried, not thrown: `GraphDocument.load()` produces readable
/// diagnostics (missing artifacts, version mismatch, layout gaps) and a developer
/// who forgot to run `ContentBuild` should be told that in the window, not shown
/// an empty one.
@MainActor
final class SceneStore {
    static let shared = SceneStore()

    private(set) var scene: GraphScene?
    private(set) var renderer: GraphRenderer?
    /// User state (§3.2). Absent only when the content itself failed to load —
    /// there is nothing to score against.
    private(set) var scores: ScoreStore?
    private(set) var errorMessage: String?
    private(set) var timings = RenderTimings()

    /// Retrievability decays continuously (§4.1), so the map has to be repainted
    /// even when nothing happens. A minute is far finer than the ramp can show —
    /// stability is measured in days — and costs one fold of a small log.
    private var decayTick: Timer?
    private static let decayInterval: TimeInterval = 60

    private init() {
        var timings = RenderTimings()
        do {
            let loadStart = CFAbsoluteTimeGetCurrent()
            let document = try GraphDocument.load()
            timings.documentLoadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000

            let buildStart = CFAbsoluteTimeGetCurrent()
            let scene = GraphScene(document: document)
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
            let scores = ScoreStore(document: document)
            self.scores = scores
            scores.onChange = { [weak renderer] in
                guard let renderer else { return }
                renderer.applyScores(scores.visuals(for: document))
                // The view pauses itself once the reveal settles, so a colour
                // write is invisible until something asks for a frame.
                renderer.requestRedraw?()
            }
            renderer.applyScores(scores.visuals(for: document))
            startDecayTick(scores)
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
}
