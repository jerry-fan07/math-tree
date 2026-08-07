import AppKit
import GraphCore
import MetalKit
import SwiftUI
import simd

/// The `MTKView` subclass that owns input. Pan, zoom, hover and click all end up
/// as camera or hover-state changes on `GraphRenderer` — none of them touch an
/// instance buffer.
final class GraphMTKView: MTKView {
    weak var graphRenderer: GraphRenderer?
    /// Nil clears the selection (click on empty space).
    var onSelect: ((NodeID?) -> Void)?
    var onHoverChanged: ((NodeID?) -> Void)?
    var onToggleSidebar: (() -> Void)?
    /// Escape, in priority order decided by the owner: close the panel first,
    /// then leave focus mode.
    var onEscape: (() -> Void)?
    /// True while focus mode covers the map (§6.2): the overlay owns the mouse
    /// by covering the view, but key equivalents would still land here — so
    /// navigation keys and any stray gestures are ignored, except Escape.
    var isNavigationSuspended = false

    private var trackingArea: NSTrackingArea?
    private var dragOrigin: SIMD2<Float>?
    private var dragDistance: Float = 0
    private var lastPoint: SIMD2<Float> = .zero

    override var acceptsFirstResponder: Bool { true }

    /// View point with the origin at the top-left, matching the drawable and the
    /// scene's screen-oriented world space.
    private func viewPoint(_ event: NSEvent) -> SIMD2<Float> {
        let point = convert(event.locationInWindow, from: nil)
        return SIMD2(Float(point.x), Float(bounds.height - point.y))
    }

    private var viewportPt: SIMD2<Float> {
        SIMD2(Float(max(bounds.width, 1)), Float(max(bounds.height, 1)))
    }

    /// The view pauses itself once the reveal has settled (see
    /// `GraphRenderer.draw(in:)`), so interaction has to ask for the frame.
    private func redraw() {
        if isPaused { draw() } else { setNeedsDisplay(bounds) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Zoom & pan

    override func scrollWheel(with event: NSEvent) {
        guard let renderer = graphRenderer, !isNavigationSuspended else { return }
        // A gesture takes the camera over from any flight in progress.
        renderer.cancelCameraFlight()
        let anchor = viewPoint(event)
        let zoomModifier =
            event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)

        if zoomModifier || !event.hasPreciseScrollingDeltas {
            // A discrete wheel notch is ~1 unit; a precise delta under a modifier
            // is finer. Both zoom toward the cursor, never the view centre.
            let steps = Float(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.03 : 0.28)
            renderer.camera.zoom(
                by: pow(1.35, steps), anchorPt: anchor, viewportPt: viewportPt,
                fitScale: renderer.fitScale)
        } else {
            renderer.camera.pan(
                byPt: SIMD2(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY)))
        }
        updateHover(at: anchor)
        redraw()
    }

    override func magnify(with event: NSEvent) {
        guard let renderer = graphRenderer, !isNavigationSuspended else { return }
        renderer.cancelCameraFlight()
        let anchor = viewPoint(event)
        renderer.camera.zoom(
            by: Float(1 + event.magnification), anchorPt: anchor, viewportPt: viewportPt,
            fitScale: renderer.fitScale)
        updateHover(at: anchor)
        redraw()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = viewPoint(event)
        dragOrigin = point
        lastPoint = point
        dragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let renderer = graphRenderer, !isNavigationSuspended else { return }
        renderer.cancelCameraFlight()
        let point = viewPoint(event)
        let delta = point - lastPoint
        lastPoint = point
        dragDistance += simd_length(delta)
        renderer.camera.pan(byPt: delta)
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        guard let renderer = graphRenderer, dragOrigin != nil, dragDistance < 4,
            !isNavigationSuspended
        else { return }
        let picked = renderer.pick(atViewPt: viewPoint(event))
        onSelect?(picked.map { renderer.scene.document.nodes[$0].id })
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: viewPoint(event))
    }

    override func mouseExited(with event: NSEvent) {
        guard let renderer = graphRenderer, renderer.hoveredIndex != nil else { return }
        renderer.setHover(nil)
        onHoverChanged?(nil)
        redraw()
    }

    private func updateHover(at point: SIMD2<Float>) {
        guard let renderer = graphRenderer, !isNavigationSuspended else { return }
        let picked = renderer.pick(atViewPt: point)
        guard picked != renderer.hoveredIndex else { return }
        renderer.setHover(picked)
        onHoverChanged?(picked.map { renderer.scene.document.nodes[$0].id })
        redraw()
    }

    override func keyDown(with event: NSEvent) {
        guard let renderer = graphRenderer else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 53:  // Escape — works in every mode; the owner decides what it closes
            onEscape?()
        case 3, 29, 82:  // F, 0, keypad 0 — frame the whole map
            guard !isNavigationSuspended else { return }
            renderer.fitToContent()
            redraw()
        case 15:  // R — show or hide the review sidebar
            guard !isNavigationSuspended else { return }
            onToggleSidebar?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// Bridges the Metal view into SwiftUI. The renderer itself is created once by
/// `SceneStore`, so this only wires input and selection.
struct GraphMetalView: NSViewRepresentable {
    let renderer: GraphRenderer
    @Binding var selection: NodeID?
    var onToggleSidebar: (() -> Void)?
    var onEscape: (() -> Void)?
    var isNavigationSuspended = false

    func makeNSView(context: Context) -> GraphMTKView {
        // The same device the renderer built its pipelines and buffers on —
        // never a second `MTLCreateSystemDefaultDevice()`.
        let view = GraphMTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(
            red: Palette.background.x, green: Palette.background.y, blue: Palette.background.z,
            alpha: 1)
        // Driven by the display link while the reveal animates; the renderer
        // pauses the view when it settles and interaction asks for single frames.
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 120
        view.delegate = renderer
        view.graphRenderer = renderer
        view.onSelect = { selection = $0 }
        view.onToggleSidebar = onToggleSidebar
        view.onEscape = onEscape
        view.isNavigationSuspended = isNavigationSuspended
        renderer.requestRedraw = { [weak view] in view?.draw() }
        return view
    }

    func updateNSView(_ view: GraphMTKView, context: Context) {
        view.onSelect = { selection = $0 }
        view.onToggleSidebar = onToggleSidebar
        view.onEscape = onEscape
        view.isNavigationSuspended = isNavigationSuspended
    }
}
