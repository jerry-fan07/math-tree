import simd

/// GPU-facing structs. Every layout here is mirrored byte-for-byte by a `struct`
/// of the same name in `ShaderSource.metal` — if one changes, both change.
///
/// Sizes are the ones Phase 3 measured and D3.4 fixed: 16 B nodes, 24 B edges,
/// 48 B labels, one 40 B uniform.

/// Camera + level-of-detail state for one frame. Uploaded with `setVertexBytes`,
/// never as a buffer — D3.4's "pan/zoom is one uniform, never a buffer rebuild".
struct Uniforms {
    /// Pixel position of world-space (0, 0) in the drawable, whose origin is top-left.
    var originPx: SIMD2<Float>
    /// Pixels per world unit — already multiplied by the backing scale.
    var scalePx: Float
    var backingScale: Float
    var viewportPx: SIMD2<Float>
    /// Progressive-reveal clock, 0…1 (§6.4). 1 = fully revealed.
    var reveal: Float
    /// Continuous zoom-band parameter: 0 = overview, 1 = deep detail. Everything
    /// that changes with zoom — node radii, edge weight, arrowheads, label fade —
    /// is a `mix()` on this, so LOD morphs instead of snapping.
    var bandT: Float
    var edgeAlpha: Float
    var labelAlpha: Float
}

/// 16 B. `radii` holds the node's radius in points at overview (`x`) and at full
/// detail (`y`); the vertex shader mixes them by `bandT`. Storing two `half`s
/// costs the same four bytes the spike spent on a single `float radiusPx`, which
/// is what buys continuous LOD without growing the instance.
struct NodeInstance {
    var pos: SIMD2<Float>
    var radii: SIMD2<Float16>
    var rgba: UInt32
}

/// 24 B. Expanded perpendicular in *screen space* by the vertex shader (D3.4) —
/// never `.line` primitives, which have no width control and no Retina AA.
struct EdgeInstance {
    var a: SIMD2<Float>
    var b: SIMD2<Float>
    var rgbaA: UInt32
    var rgbaB: UInt32
}

/// 48 B, sampling an R8 `texture2d_array` atlas.
struct LabelInstance {
    /// World position of the node this label belongs to.
    var anchor: SIMD2<Float>
    /// Label box in points — labels are screen-space sized, so they stay legible
    /// at every zoom instead of scaling with the map.
    var sizePt: SIMD2<Float>
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
    var rgba: UInt32
    /// Slice of the atlas array texture.
    var page: UInt32
    /// Vertical gap from the node centre to the top of the label box, in points.
    var offsetPt: Float
    /// `bandT` at which this label starts to fade in. Negative = always visible.
    var fadeStart: Float
}

/// 40 B of per-draw-call constants, shared by all three pipelines (each uses the
/// subset it needs). Passed with `setVertexBytes`, so varying edge style between
/// classes costs no buffer traffic.
struct DrawParams {
    /// Index of the first instance of this draw within its buffer.
    var rangeStart: UInt32
    /// Denominator for the reveal ramp — the class's full instance count.
    var count: Float
    /// Reveal window: instance *i* appears at `revealBase + revealSpan * i/count`.
    var revealBase: Float
    var revealSpan: Float
    var alpha: Float
    /// Edges only, in points; already mixed for the current band.
    var widthPt: Float
    var dashPeriodPt: Float
    /// Fraction of each dash period that is drawn. 1 = solid.
    var dashDuty: Float
    var arrowAlpha: Float
    var arrowSizePt: Float
}

extension DrawParams {
    static func nodes(count: Int, revealBase: Float, revealSpan: Float, alpha: Float) -> DrawParams {
        DrawParams(
            rangeStart: 0, count: Float(max(count, 1)), revealBase: revealBase,
            revealSpan: revealSpan, alpha: alpha, widthPt: 0, dashPeriodPt: 0,
            dashDuty: 1, arrowAlpha: 0, arrowSizePt: 0)
    }
}

/// Packs a colour into the rgba8 word the shaders unpack. Components are
/// straight (non-premultiplied) here; the fragment shaders premultiply on the
/// way out, matching the `.one` / `.oneMinusSourceAlpha` blend of D3.4.
func packRGBA(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> UInt32 {
    func byte(_ v: Float) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
    return byte(r) | (byte(g) << 8) | (byte(b) << 16) | (byte(a) << 24)
}
