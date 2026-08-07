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
    private(set) var errorMessage: String?
    private(set) var timings = RenderTimings()

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
        } catch {
            self.timings = timings
            errorMessage = String(describing: error)
        }
    }
}
