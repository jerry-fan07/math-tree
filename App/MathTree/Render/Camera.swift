import simd

/// The three zoom levels §6.1 specifies. Bands are expressed as multiples of the
/// fit-to-view scale rather than absolute scale, so they mean the same thing at
/// 27 nodes and at 10,000: "the whole map", "a subbranch neighbourhood", "one
/// node and its neighbours".
enum ZoomBand: String, CaseIterable, Sendable {
    case overview
    case mid
    case detail

    /// Upper bound of the band as a multiple of fit-to-view scale.
    static let midRatio: Float = 1.6
    static let detailRatio: Float = 4.0
    /// `bandT` saturates here — 8× fit is as deep as LOD morphing goes.
    static let maxRatio: Float = 8.0

    static func band(forRatio ratio: Float) -> ZoomBand {
        if ratio < midRatio { return .overview }
        if ratio < detailRatio { return .mid }
        return .detail
    }

    /// A representative zoom inside the band — the geometric midpoint, or the
    /// endpoints for the two open-ended bands. Used by `--probe` and snapshots so
    /// "at overview zoom" is a definite, reproducible camera.
    var representativeRatio: Float {
        switch self {
        case .overview: 1.0
        case .mid: 2.5
        case .detail: 4.5
        }
    }

    static func bandT(forRatio ratio: Float) -> Float {
        let clamped = max(ratio, 1e-4)
        return min(max(log2(clamped) / log2(maxRatio), 0), 1)
    }
}

/// Pan/zoom state. Everything here ends up in the 40-byte uniform; nothing here
/// ever touches an instance buffer (D3.4).
struct Camera {
    /// World point sitting at the centre of the viewport.
    var center: SIMD2<Float> = .zero
    /// Points per world unit.
    var scale: Float = 1

    /// Zoom limits relative to fit-to-view. The lower bound keeps the map from
    /// vanishing; the upper bound keeps `scalePx` well inside float precision.
    static let minRatio: Float = 0.25
    static let maxRatio: Float = 16.0

    func originPx(viewportPx: SIMD2<Float>, backingScale: Float) -> SIMD2<Float> {
        viewportPx * 0.5 - center * (scale * backingScale)
    }

    func world(fromViewPt point: SIMD2<Float>, viewportPt: SIMD2<Float>) -> SIMD2<Float> {
        center + (point - viewportPt * 0.5) / scale
    }

    func viewPt(fromWorld point: SIMD2<Float>, viewportPt: SIMD2<Float>) -> SIMD2<Float> {
        viewportPt * 0.5 + (point - center) * scale
    }

    /// Zoom toward a point in the viewport rather than the view centre — the
    /// thing that makes trackpad zoom feel like a map instead of a slider.
    mutating func zoom(
        by factor: Float, anchorPt: SIMD2<Float>, viewportPt: SIMD2<Float>, fitScale: Float
    ) {
        guard factor.isFinite, factor > 0 else { return }
        let anchorWorld = world(fromViewPt: anchorPt, viewportPt: viewportPt)
        let target = scale * factor
        let clamped = min(max(target, fitScale * Camera.minRatio), fitScale * Camera.maxRatio)
        guard clamped.isFinite, clamped > 0 else { return }
        scale = clamped
        center = anchorWorld + (viewportPt * 0.5 - anchorPt) / scale
    }

    mutating func pan(byPt delta: SIMD2<Float>) {
        guard delta.x.isFinite, delta.y.isFinite, scale > 0 else { return }
        center -= delta / scale
    }

    mutating func fit(scene: GraphScene, viewportPt: SIMD2<Float>) {
        center = scene.center
        scale = scene.fitScale(viewportPt: viewportPt)
    }

    func ratio(fitScale: Float) -> Float { scale / max(fitScale, 1e-6) }
    func bandT(fitScale: Float) -> Float { ZoomBand.bandT(forRatio: ratio(fitScale: fitScale)) }
    func band(fitScale: Float) -> ZoomBand { ZoomBand.band(forRatio: ratio(fitScale: fitScale)) }
}
