import Foundation
import GraphCore
import Metal
import MetalKit
import simd

enum RendererError: Error, CustomStringConvertible {
    case noDevice
    case shaderCompileFailed(String)
    case missingFunction(String)
    case pipelineFailed(String)
    case offscreenTargetFailed

    var description: String {
        switch self {
        case .noDevice: "No Metal device available on this machine."
        case let .shaderCompileFailed(message): "Metal shader compile failed: \(message)"
        case let .missingFunction(name): "Shader function \(name) not found in the compiled library."
        case let .pipelineFailed(message): "Render pipeline creation failed: \(message)"
        case .offscreenTargetFailed: "Could not allocate the offscreen render target."
        }
    }
}

/// Timing breakdown for `--probe`, filled in as the renderer comes up.
struct RenderTimings: Sendable {
    var documentLoadMs = 0.0
    var sceneBuildMs = 0.0
    var shaderCompileMs = 0.0
    var pipelineMs = 0.0
    var instanceBufferMs = 0.0
    var labelAtlasMs = 0.0
}

/// Three static instance buffers, one 40-byte uniform, a handful of draw calls,
/// zero per-frame uploads — the frame architecture D3.4 handed to Phase 4.
///
/// The one deliberate departure from "three draw calls": edges are split into
/// `contains` / `requires` / `relates` so each class can carry its own width,
/// alpha, dash and arrowhead style through `setVertexBytes`. That is what §6.1's
/// mid-zoom distinction requires, and it costs no buffer traffic — the property
/// the spike actually measured (0.13 ms CPU encode) was zero per-frame uploads,
/// not the literal draw count.
@MainActor
final class GraphRenderer: NSObject, MTKViewDelegate {
    let scene: GraphScene
    private(set) var timings: RenderTimings

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let nodePipeline: MTLRenderPipelineState
    private let ringPipeline: MTLRenderPipelineState
    private let edgePipeline: MTLRenderPipelineState
    private let labelPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private let nodeBuffer: MTLBuffer?
    private var edgeBuffers: [MTLBuffer?]
    private let labelBuffer: MTLBuffer?
    private let highlightNodeBuffer: MTLBuffer?
    private let highlightEdgeBuffer: MTLBuffer?
    private static let highlightCapacity = 512
    /// §4.5's frontier accent rings. Sized for every node at once — the frontier
    /// can legitimately be most of the map on a fresh user.
    private let frontierRingBuffer: MTLBuffer?
    private(set) var frontierRingCount = 0

    private let atlas: LabelAtlas

    var camera = Camera()
    private(set) var viewportPx = SIMD2<Float>(1, 1)
    private(set) var backingScale: Float = 2

    /// Progressive reveal (§6.4): hubs first, then constellation fill.
    private var revealStart: CFAbsoluteTime = 0
    private static let revealDuration: CFAbsoluteTime = 0.65
    private var revealOverride: Float?

    /// §6.2's "zoom-out, not a cut". Camera state is one 40-byte uniform, so the
    /// transition is uniform-only — zero buffer traffic, per-frame cost identical
    /// to a settled frame (D3.4). Stepped in `draw(in:)` like the reveal.
    private struct CameraFlight {
        var from: Camera
        var to: Camera
        var start: CFAbsoluteTime
        var duration: CFAbsoluteTime
    }
    private var cameraFlight: CameraFlight?

    private(set) var hoveredIndex: Int?
    private var highlightNodeCount = 0
    private var highlightEdgeCount = 0

    /// Hook for `--probe`. Called on the main actor as the *first* frame is
    /// encoded — when the viewport is finally known — and returns the closure the
    /// command buffer's completion handler runs. Splitting it this way keeps every
    /// main-actor read on the main actor: `MTLCommandBuffer` completion handlers
    /// are `@Sendable` and run off-thread.
    var makeFirstDrawCompletion: ((GraphRenderer) -> (@Sendable () -> Void))?
    private var firstDrawDispatched = false

    /// Set by the view when it wants a redraw scheduled outside the reveal
    /// animation (hover, pan, zoom).
    var requestRedraw: (() -> Void)?

    init(device: MTLDevice, scene: GraphScene, timings: RenderTimings, backingScale: CGFloat) throws
    {
        self.device = device
        self.scene = scene
        self.timings = timings
        self.backingScale = Float(max(backingScale, 1))

        guard let queue = device.makeCommandQueue() else { throw RendererError.noDevice }
        commandQueue = queue

        // D0.3: runtime compilation. SwiftPM will not build a `.metal` file in a
        // Swift target, so the source travels as a string and Metal caches the
        // compile on its text.
        let compileStart = CFAbsoluteTimeGetCurrent()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ShaderSource.metal, options: nil)
        } catch {
            throw RendererError.shaderCompileFailed(String(describing: error))
        }
        self.timings.shaderCompileMs = (CFAbsoluteTimeGetCurrent() - compileStart) * 1000

        let pipelineStart = CFAbsoluteTimeGetCurrent()
        func function(_ name: String) throws -> MTLFunction {
            guard let f = library.makeFunction(name: name) else {
                throw RendererError.missingFunction(name)
            }
            return f
        }
        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = try function(vertex)
            descriptor.fragmentFunction = try function(fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = .bgra8Unorm
            attachment.isBlendingEnabled = true
            // Premultiplied source (D3.4) — every fragment shader here multiplies
            // rgb by alpha on the way out.
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw RendererError.pipelineFailed(String(describing: error))
            }
        }
        nodePipeline = try pipeline("nodeVertex", "nodeFragment")
        ringPipeline = try pipeline("nodeVertex", "ringFragment")
        edgePipeline = try pipeline("edgeVertex", "edgeFragment")
        labelPipeline = try pipeline("labelVertex", "labelFragment")

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw RendererError.pipelineFailed("sampler")
        }
        self.sampler = sampler
        self.timings.pipelineMs = (CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000

        let bufferStart = CFAbsoluteTimeGetCurrent()
        func staticBuffer<T>(_ array: [T]) -> MTLBuffer? {
            guard !array.isEmpty else { return nil }
            return array.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            }
        }
        nodeBuffer = staticBuffer(scene.nodeInstances)
        edgeBuffers = scene.edges.map(staticBuffer)
        // Allocated at full capacity once; tiers are written into it as they are
        // rasterised, so this is still a static buffer — it grows at zoom-band
        // boundaries, never per frame.
        labelBuffer = scene.labelSpecs.isEmpty
            ? nil
            : device.makeBuffer(
                length: scene.labelSpecs.count * MemoryLayout<LabelInstance>.stride,
                options: .storageModeShared)
        highlightNodeBuffer = device.makeBuffer(
            length: Self.highlightCapacity * MemoryLayout<NodeInstance>.stride,
            options: .storageModeShared)
        highlightEdgeBuffer = device.makeBuffer(
            length: Self.highlightCapacity * MemoryLayout<EdgeInstance>.stride,
            options: .storageModeShared)
        frontierRingBuffer = scene.nodeInstances.isEmpty
            ? nil
            : device.makeBuffer(
                length: scene.nodeInstances.count * MemoryLayout<NodeInstance>.stride,
                options: .storageModeShared)
        self.timings.instanceBufferMs = (CFAbsoluteTimeGetCurrent() - bufferStart) * 1000

        atlas = LabelAtlas(device: device, backingScale: backingScale)
        super.init()

        // D3.5: the overview tier is rasterised eagerly because it is on the
        // first-paint path and costs milliseconds; deeper tiers wait for a band
        // that wants them, because atlas *memory* is the constraint that bites.
        buildLabels(upTo: .landmark)
        self.timings.labelAtlasMs = atlas.stats.rasteriseMs
        revealStart = CFAbsoluteTimeGetCurrent()
    }

    // MARK: - Labels

    private func buildLabels(upTo tier: LODTier) {
        guard atlas.build(upTo: tier, specs: scene.labelSpecs), let labelBuffer else { return }
        atlas.instances.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            memcpy(labelBuffer.contents(), base, min(source.count, labelBuffer.length))
        }
    }

    var atlasStats: LabelAtlas.Stats { atlas.stats }

    // MARK: - Camera

    var viewportPt: SIMD2<Float> { viewportPx / backingScale }
    var fitScale: Float { scene.fitScale(viewportPt: viewportPt) }
    var bandT: Float { camera.bandT(fitScale: fitScale) }
    var band: ZoomBand { camera.band(fitScale: fitScale) }

    func resize(drawablePx: SIMD2<Float>, backingScale: CGFloat) {
        let wasUnset = viewportPx.x <= 1
        viewportPx = SIMD2(max(drawablePx.x, 1), max(drawablePx.y, 1))
        self.backingScale = Float(max(backingScale, 1))
        if wasUnset { camera.fit(scene: scene, viewportPt: viewportPt) }
    }

    func fitToContent() {
        camera.fit(scene: scene, viewportPt: viewportPt)
    }

    /// Bring a node into view — how the node panel's prerequisite links navigate.
    func center(on id: GraphCore.NodeID) {
        guard let index = scene.document.index(of: id) else { return }
        camera.center = scene.worldPositions[index]
        if camera.ratio(fitScale: fitScale) < ZoomBand.detailRatio {
            camera.scale = fitScale * ZoomBand.detailRatio
        }
        requestRedraw?()
    }

    /// Fly the camera to a target — the focus-mode transition (§6.2: continuity
    /// of place, so entering and leaving focus is a zoom, never a cut).
    ///
    /// Scale interpolates in log space (a zoom is perceptually multiplicative)
    /// and the camera snaps to the exact target at the end, so the destination
    /// is a definite camera rather than wherever t ≈ 1 landed. The kick matters:
    /// the view pauses itself when settled, so a flight started without a
    /// redraw request would never take off.
    func flyCamera(toCenter center: SIMD2<Float>, scale: Float, duration: CFAbsoluteTime = 0.5) {
        var target = Camera(center: center, scale: scale)
        let fit = fitScale
        target.scale = min(max(target.scale, fit * Camera.minRatio), fit * Camera.maxRatio)
        cameraFlight = CameraFlight(
            from: camera, to: target, start: CFAbsoluteTimeGetCurrent(), duration: duration)
        requestRedraw?()
    }

    func flyCamera(to target: Camera, duration: CFAbsoluteTime = 0.5) {
        flyCamera(toCenter: target.center, scale: target.scale, duration: duration)
    }

    /// A goal-node camera for focus mode: centred on the node, at detail zoom.
    func focusCamera(on id: GraphCore.NodeID) -> Camera? {
        guard let index = scene.document.index(of: id) else { return nil }
        return Camera(
            center: scene.worldPositions[index],
            scale: fitScale * ZoomBand.detailRatio)
    }

    /// Advance the flight; interaction cancels it implicitly because pan/zoom
    /// write `camera` directly and the next `stepCameraFlight` overwrites — so a
    /// flight is cancelled by *ending* it early instead.
    private func stepCameraFlight() {
        guard let flight = cameraFlight else { return }
        let t = min(max((CFAbsoluteTimeGetCurrent() - flight.start) / flight.duration, 0), 1)
        if t >= 1 {
            camera = flight.to
            cameraFlight = nil
            return
        }
        let eased = Float(t * t * (3 - 2 * t))
        camera.center = flight.from.center + (flight.to.center - flight.from.center) * eased
        camera.scale = exp(
            log(max(flight.from.scale, 1e-6)) * (1 - eased)
                + log(max(flight.to.scale, 1e-6)) * eased)
    }

    /// End any flight in progress (a user gesture takes over the camera).
    func cancelCameraFlight() { cameraFlight = nil }

    var isCameraInFlight: Bool { cameraFlight != nil }

    /// Park the camera at a band's representative zoom over a chosen anchor —
    /// used by snapshots and `--probe` so "at mid zoom" is a definite camera.
    func park(at band: ZoomBand, anchor: SIMD2<Float>?) {
        let fit = scene.fitScale(viewportPt: viewportPt)
        camera.scale = fit * band.representativeRatio
        camera.center = anchor ?? scene.center
        buildLabels(upTo: scene.requiredLabelTier(bandT: bandT))
    }

    // MARK: - Interaction

    func world(atViewPt point: SIMD2<Float>) -> SIMD2<Float> {
        camera.world(fromViewPt: point, viewportPt: viewportPt)
    }

    /// Nearest node under a point in view coordinates, honouring the radius that
    /// node actually has at the current band.
    func pick(atViewPt point: SIMD2<Float>) -> Int? {
        let worldPoint = world(atViewPt: point)
        let slackPt: Float = 5
        let searchWorld = (scene.maxNodeRadiusPt + slackPt) / max(camera.scale, 1e-6)
        guard let candidate = scene.pickGrid.nearest(to: worldPoint, within: searchWorld) else {
            return nil
        }
        let radii = scene.tierByDocumentIndex[candidate].radiiPt
        let radiusPt = radii.overview + (radii.detail - radii.overview) * bandT
        let reach = (radiusPt + slackPt) / max(camera.scale, 1e-6)
        let delta = scene.worldPositions[candidate] - worldPoint
        return simd_length(delta) <= reach ? candidate : nil
    }

    /// §6.1 detail zoom: hovering highlights the node's direct prerequisites and
    /// dependents. Written only when the hover target changes — never per frame.
    func setHover(_ documentIndex: Int?) {
        guard documentIndex != hoveredIndex else { return }
        hoveredIndex = documentIndex
        rebuildHighlight()
    }

    private func rebuildHighlight() {
        highlightNodeCount = 0
        highlightEdgeCount = 0
        guard let hovered = hoveredIndex,
            let nodeBuffer = highlightNodeBuffer, let edgeBuffer = highlightEdgeBuffer
        else { return }

        let document = scene.document
        let node = document.nodes[hovered]
        var rings: [NodeInstance] = []
        var lines: [EdgeInstance] = []

        func radius(_ index: Int, _ boost: Float) -> Float {
            let radii = scene.tierByDocumentIndex[index].radiiPt
            return max(radii.overview, radii.detail) * boost + 3.5
        }
        func ring(_ index: Int, _ color: UInt32, _ boost: Float) {
            let r = Float16(radius(index, boost))
            rings.append(
                NodeInstance(pos: scene.worldPositions[index], radii: SIMD2(r, r), rgba: color))
        }

        ring(hovered, Palette.hoverRingColor, 1.75)
        for prerequisite in node.requires {
            guard let index = document.index(of: prerequisite), rings.count < Self.highlightCapacity
            else { continue }
            ring(index, Palette.prerequisiteRingColor, 1.55)
            lines.append(
                EdgeInstance(
                    a: scene.worldPositions[index], b: scene.worldPositions[hovered],
                    rgbaA: Palette.prerequisiteRingColor, rgbaB: Palette.highlightEdgeColor))
        }
        for dependent in document.dependents(of: node.id) {
            guard let index = document.index(of: dependent), rings.count < Self.highlightCapacity
            else { continue }
            ring(index, Palette.dependentRingColor, 1.55)
            lines.append(
                EdgeInstance(
                    a: scene.worldPositions[hovered], b: scene.worldPositions[index],
                    rgbaA: Palette.highlightEdgeColor, rgbaB: Palette.dependentRingColor))
        }

        highlightNodeCount = min(rings.count, Self.highlightCapacity)
        highlightEdgeCount = min(lines.count, Self.highlightCapacity)
        rings.withUnsafeBytes {
            guard let base = $0.baseAddress else { return }
            memcpy(nodeBuffer.contents(), base, min($0.count, nodeBuffer.length))
        }
        lines.withUnsafeBytes {
            guard let base = $0.baseAddress else { return }
            memcpy(edgeBuffer.contents(), base, min($0.count, edgeBuffer.length))
        }
    }

    // MARK: - Scores

    /// The last snapshot applied — kept so the probe can print the colours that
    /// were actually drawn rather than recompute them and hope they agree.
    private(set) var scoreVisuals: ScoreVisuals?

    /// Repaint the map for one score snapshot (§4.5).
    ///
    /// This rewrites colour words inside buffers that already exist; it never
    /// rebuilds or reallocates one. D3.4's invariant is *zero per-frame uploads*,
    /// and a review or a decay tick is neither — the same pattern the hover
    /// highlight has used since Phase 4.
    func applyScores(_ visuals: ScoreVisuals) {
        guard visuals.nodeColor.count == scene.document.nodes.count else { return }
        scoreVisuals = visuals
        writeNodeColors(visuals)
        writeEdgeColors(visuals)
        rebuildFrontierRings(visuals)
    }

    /// The colour words the GPU is actually holding, by document index. Read back
    /// from the buffer rather than recomputed: the probe's determinism claim is
    /// about what was *drawn*, and a recomputation would agree with itself even if
    /// `applyScores` had never run.
    func packedNodeColors() -> [UInt32] {
        guard let nodeBuffer else { return [] }
        let instances = nodeBuffer.contents()
            .bindMemory(to: NodeInstance.self, capacity: scene.nodeInstances.count)
        return (0..<scene.document.nodes.count).map {
            instances[scene.instanceIndexByDocument[$0]].rgba
        }
    }

    private func writeNodeColors(_ visuals: ScoreVisuals) {
        guard let nodeBuffer else { return }
        let instances = nodeBuffer.contents()
            .bindMemory(to: NodeInstance.self, capacity: scene.nodeInstances.count)
        for (documentIndex, color) in visuals.nodeColor.enumerated() {
            let tier = scene.tierByDocumentIndex[documentIndex]
            instances[scene.instanceIndexByDocument[documentIndex]].rgba =
                color.map { Palette.scoreNodeColor($0, tier: tier) }
                // Structural: not learnable, so it keeps its taxonomy hue (D6.1).
                ?? Palette.nodeColor(hue: scene.hueByDocumentIndex[documentIndex], tier: tier)
        }
    }

    /// §6.1: "edges inherit blended endpoint colours; `relates` edges show their
    /// own score". `contains` is left alone — it joins a structural parent that
    /// has no score, and it is the filament that makes branches read as galaxies.
    private func writeEdgeColors(_ visuals: ScoreVisuals) {
        func endpointColor(_ documentIndex: Int, weight: Float) -> UInt32 {
            guard let color = visuals.nodeColor[documentIndex] else {
                return Palette.edgeColor(
                    hue: scene.hueByDocumentIndex[documentIndex],
                    tier: scene.tierByDocumentIndex[documentIndex], weight: weight)
            }
            return Palette.scoreEdgeColor(color, weight: weight)
        }

        for edgeClass in [GraphScene.EdgeClass.requires, .relates] {
            guard let buffer = edgeBuffers[edgeClass.rawValue] else { continue }
            let endpoints = scene.edgeEndpoints[edgeClass.rawValue]
            let instances = buffer.contents()
                .bindMemory(to: EdgeInstance.self, capacity: endpoints.count)
            // Phase 4's directional weights are kept: a `requires` edge stays dim
            // at the prerequisite and bright at the dependent, so it still reads
            // as flow rather than as a symmetric link.
            let weights: (Float, Float) = edgeClass == .requires ? (0.55, 1.0) : (0.85, 0.85)

            for (instance, endpoint) in endpoints.enumerated() {
                // §4.4: an exercised connection is knowledge over and above its
                // endpoints, so it overrides the blend with its own score.
                if edgeClass == .relates, instance < scene.relatesSourceByInstance.count {
                    let source = scene.relatesSourceByInstance[instance]
                    if source >= 0, source < visuals.relatesColor.count,
                        let own = visuals.relatesColor[source]
                    {
                        let packed = Palette.scoreEdgeColor(own, weight: 0.85)
                        instances[instance].rgbaA = packed
                        instances[instance].rgbaB = packed
                        continue
                    }
                }
                instances[instance].rgbaA = endpointColor(endpoint.from, weight: weights.0)
                instances[instance].rgbaB = endpointColor(endpoint.to, weight: weights.1)
            }
        }
    }

    /// §4.5's frontier ring: the fill stays unlearned grey and the accent is added
    /// around it, because being on the frontier is a fact about the graph around a
    /// node rather than a score the node carries.
    private func rebuildFrontierRings(_ visuals: ScoreVisuals) {
        frontierRingCount = 0
        guard let frontierRingBuffer else { return }
        var rings: [NodeInstance] = []
        rings.reserveCapacity(visuals.isFrontier.count)
        for (documentIndex, isFrontier) in visuals.isFrontier.enumerated() where isFrontier {
            let radii = scene.tierByDocumentIndex[documentIndex].radiiPt
            rings.append(
                NodeInstance(
                    pos: scene.worldPositions[documentIndex],
                    // Keeps the band morph the node itself has, so the ring never
                    // detaches from the dot it belongs to as the zoom changes.
                    radii: SIMD2(
                        Float16(radii.overview * 1.55 + 2.2), Float16(radii.detail * 1.55 + 2.2)),
                    rgba: Palette.frontierRingColor))
        }
        frontierRingCount = min(rings.count, scene.nodeInstances.count)
        rings.withUnsafeBytes {
            guard let base = $0.baseAddress else { return }
            memcpy(frontierRingBuffer.contents(), base, min($0.count, frontierRingBuffer.length))
        }
    }

    // MARK: - Frame

    private var reveal: Float {
        if let revealOverride { return revealOverride }
        let elapsed = CFAbsoluteTimeGetCurrent() - revealStart
        return Float(min(max(elapsed / Self.revealDuration, 0), 1))
    }

    /// Freeze the reveal clock. Snapshots want a settled scene (1) by default,
    /// but pinning it part-way is the only way to capture §6.4's "hubs fade in
    /// first, then constellation fill" in a still image.
    func setReveal(_ value: Float) { revealOverride = min(max(value, 0), 1) }

    var isAnimating: Bool { (revealOverride == nil && reveal < 1) || cameraFlight != nil }

    private func makeUniforms() -> Uniforms {
        Uniforms(
            originPx: camera.originPx(viewportPx: viewportPx, backingScale: backingScale),
            scalePx: camera.scale * backingScale,
            backingScale: backingScale,
            viewportPx: viewportPx,
            reveal: reveal,
            bandT: bandT,
            edgeAlpha: 1,
            labelAlpha: 1)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / max(edge1 - edge0, 1e-6), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    /// Per-class edge styling, mixed for the current band. §6.1: `contains`
    /// dominates at overview so branches read as galaxies; by mid zoom `requires`
    /// has taken over and carries arrowheads, while `relates` goes dashed and faint.
    func edgeParams(_ edgeClass: GraphScene.EdgeClass, count: Int, bandT t: Float)
        -> DrawParams
    {
        let mix = Self.mix
        let arrowRamp = Self.smoothstep(0.18, 0.38, t)
        let dashRamp = Self.smoothstep(0.18, 0.40, t)
        switch edgeClass {
        case .contains:
            return DrawParams(
                rangeStart: 0, count: Float(max(count, 1)), revealBase: 0.10, revealSpan: 0.30,
                alpha: mix(0.50, 0.16, t), widthPt: mix(1.0, 0.7, t), dashPeriodPt: 0,
                dashDuty: 1, arrowAlpha: 0, arrowSizePt: 0)
        case .requires:
            return DrawParams(
                rangeStart: 0, count: Float(max(count, 1)), revealBase: 0.38, revealSpan: 0.32,
                alpha: mix(0.24, 0.70, t), widthPt: mix(1.1, 1.7, t), dashPeriodPt: 0,
                dashDuty: 1, arrowAlpha: 0.85 * arrowRamp, arrowSizePt: mix(6.0, 9.0, t))
        case .relates:
            return DrawParams(
                rangeStart: 0, count: Float(max(count, 1)), revealBase: 0.52, revealSpan: 0.26,
                alpha: mix(0.18, 0.55, t), widthPt: mix(1.0, 1.4, t),
                dashPeriodPt: mix(7.0, 10.0, t), dashDuty: mix(1.0, 0.50, dashRamp),
                arrowAlpha: 0, arrowSizePt: 0)
        }
    }

    func encode(into encoder: MTLRenderCommandEncoder) {
        var uniforms = makeUniforms()
        let t = uniforms.bandT
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        func draw(
            _ pipeline: MTLRenderPipelineState, _ buffer: MTLBuffer?, _ count: Int,
            _ params: DrawParams, texture: MTLTexture? = nil
        ) {
            guard let buffer, count > 0 else { return }
            var params = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 1)
            encoder.setVertexBytes(&params, length: MemoryLayout<DrawParams>.stride, index: 2)
            if let texture {
                encoder.setVertexTexture(texture, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(sampler, index: 0)
            }
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }

        // Edges under nodes under labels — painter's order, no depth buffer.
        for edgeClass in GraphScene.EdgeClass.allCases {
            let count = scene.edgePrefix(edgeClass, bandT: t)
            draw(
                edgePipeline, edgeBuffers[edgeClass.rawValue], count,
                edgeParams(edgeClass, count: count, bandT: t))
        }

        let highlightAlpha = Self.smoothstep(0.45, 0.70, t)
        if highlightAlpha > 0.01, highlightEdgeCount > 0 {
            draw(
                edgePipeline, highlightEdgeBuffer, highlightEdgeCount,
                DrawParams(
                    rangeStart: 0, count: 1, revealBase: 0, revealSpan: 0,
                    alpha: 0.85 * highlightAlpha, widthPt: 2.0, dashPeriodPt: 0, dashDuty: 1,
                    arrowAlpha: 0, arrowSizePt: 0))
        }

        // LOD as an instance-count prefix (D3.4), not a rebuild.
        draw(
            nodePipeline, nodeBuffer,
            scene.nodePrefix(bandT: t, backingScale: backingScale),
            DrawParams.nodes(count: scene.nodeInstances.count, revealBase: 0.02, revealSpan: 0.42, alpha: 1))

        // §4.5's frontier accent, over the node fills and under the hover ring.
        // Visible at every band, unlike the hover highlight: the frontier is what
        // the whole product points at, so it must be legible from the overview.
        // It arrives last in the reveal, after the constellation has filled in.
        if frontierRingCount > 0 {
            draw(
                ringPipeline, frontierRingBuffer, frontierRingCount,
                DrawParams.nodes(count: 1, revealBase: 0.55, revealSpan: 0, alpha: 1))
        }

        if highlightAlpha > 0.01, highlightNodeCount > 0 {
            draw(
                ringPipeline, highlightNodeBuffer, highlightNodeCount,
                DrawParams.nodes(count: 1, revealBase: 0, revealSpan: 0, alpha: highlightAlpha))
        }

        let labelCount = min(scene.labelPrefix(bandT: t), atlas.builtCount)
        draw(
            labelPipeline, labelBuffer, labelCount,
            DrawParams.nodes(
                count: scene.labelSpecs.count, revealBase: 0.50, revealSpan: 0.34, alpha: 1),
            texture: atlas.texture)
    }

    /// Rasterise any label tier this band has just brought into view. Called
    /// before encoding, so a zoom that crosses a band boundary pays once.
    func prepareForCurrentBand() {
        buildLabels(upTo: scene.requiredLabelTier(bandT: bandT))
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resize(
            drawablePx: SIMD2(Float(size.width), Float(size.height)),
            backingScale: view.window?.backingScaleFactor ?? 2)
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        stepCameraFlight()
        prepareForCurrentBand()
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Palette.background.x, green: Palette.background.y,
            blue: Palette.background.z, alpha: 1)

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encode(into: encoder)
            encoder.endEncoding()
        }

        if !firstDrawDispatched, let make = makeFirstDrawCompletion {
            firstDrawDispatched = true
            let completion = make(self)
            commandBuffer.addCompletedHandler { _ in completion() }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        view.isPaused = !isAnimating
    }

    // MARK: - Offscreen

    /// Render one frame into a texture we own. D3.7: profile offscreen — an
    /// on-screen `MTKView` cannot be uncapped and its GPU timestamps are inflated
    /// ~3× by drawable scheduling. This is also how snapshots are produced,
    /// which means they need no window server.
    func renderOffscreen(widthPx: Int, heightPx: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: widthPx, height: heightPx, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: descriptor),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { throw RendererError.offscreenTargetFailed }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Palette.background.x, green: Palette.background.y,
            blue: Palette.background.z, alpha: 1)

        prepareForCurrentBand()
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw RendererError.offscreenTargetFailed
        }
        encode(into: encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return texture
    }
}
