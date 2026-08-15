import CoreGraphics
import GraphCore
import simd

/// Level-of-detail tier. The order *is* the buffer order: instances are sorted
/// by tier once at load, so a zoom level becomes a `drawPrimitives(instanceCount:)`
/// prefix rather than a buffer rebuild (D3.4).
enum LODTier: Int, CaseIterable, Sendable, Comparable {
    case branch = 0
    case subbranch = 1
    case landmark = 2
    case standard = 3
    case detail = 4

    static func < (lhs: LODTier, rhs: LODTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .branch: "branch"
        case .subbranch: "subbranch"
        case .landmark: "prominence-2"
        case .standard: "prominence-1"
        case .detail: "prominence-0"
        }
    }

    /// Structural kind wins over authored prominence — §2.1 makes hubs
    /// "implicitly maximal prominence for display purposes".
    init(node: Node) {
        switch node.kind {
        case .branch: self = .branch
        case .subbranch: self = .subbranch
        default:
            switch node.prominence {
            case .landmark: self = .landmark
            case .standard: self = .standard
            case .detail: self = .detail
            }
        }
    }

    /// Node radius in points at overview and at full detail. §6.1: hubs render
    /// large at overview and `prominence: 0` shrinks to near-dots — here that is
    /// a 5× span between a branch hub and a detail node.
    ///
    /// The redesign shrinks every tier: it recreated Phase 6's sizes for
    /// comparison and then chose roughly half of them. That is the whole
    /// difference between a map of dots and a map of blobs — at the old sizes the
    /// hue-per-branch fills merge into discs of colour and the `contains`
    /// filaments disappear underneath their own endpoints.
    var radiiPt: (overview: Float, detail: Float) {
        switch self {
        case .branch: (9.0, 11.0)
        case .subbranch: (5.0, 7.0)
        case .landmark: (3.5, 5.5)
        case .standard: (2.5, 4.0)
        case .detail: (1.7, 2.9)
        }
    }

    /// `bandT` at which this tier's labels begin to fade in. Negative means
    /// "already visible at overview" — hubs and landmarks, per §6.1.
    var labelFadeStart: Float {
        switch self {
        case .branch, .subbranch, .landmark: -1.0
        case .standard: 0.28
        case .detail: 0.66
        }
    }

    var labelPointSize: CGFloat {
        switch self {
        case .branch: 11.0
        case .subbranch: 12.5
        case .landmark: 11.5
        case .standard: 10.5
        case .detail: 9.5
        }
    }

    /// Mean glyph advance as a fraction of the point size, for `LabelCull`'s box
    /// estimate. Branch names are mono *and* tracked at 0.16 em, which is why they
    /// are so much wider per character than the sans tiers.
    var labelAdvanceRatio: Float {
        switch self {
        case .branch: 0.78
        default: 0.56
        }
    }
}

/// Two colour systems, split by what a node *is* — resolved against a `Theme`.
///
/// Phase 4 gave every node a branch hue, which is what makes `contains`
/// clustering readable. Phase 6 handed §4.5's nodes to a hue ramp: blue when
/// decayed through teal to green when solid. The redesign takes the hue back and
/// gives §4.5 *luminance* instead — a node's hue says which branch of mathematics
/// it is in, and how bright (dark) or how dense (light) it is says how well it is
/// known. Two independent channels instead of one contested one, which is what
/// lets the overview show both the taxonomy and the score at the same time.
///
/// Structural hubs are exempt as before: they are not learnable (§2.1), so they
/// take no score colour and the redesign paints them near-neutral rather than
/// hued, leaving the branch hues entirely to the content (D11.1, which is where
/// D6.1's desaturated hubs were heading).
enum Palette {
    /// Curated first, golden-angle after. Hand-picked hues keep the first handful
    /// of branches maximally distinguishable; the generator keeps the scheme
    /// working when the corpus grows past them (§7: ~15 branches).
    ///
    /// The seeds are unchanged from Phase 4 — the redesign reuses the same numbers
    /// — but they are now read as Oklch hue angles rather than HSV ones, which is
    /// what makes an equal score read equally bright across all twelve branches.
    private static let seedHues: [Float] = [205, 152, 38, 276, 12, 96, 320, 178, 58, 240]

    static func hue(forBranchIndex index: Int) -> Float {
        if index < seedHues.count { return seedHues[index] }
        return (seedHues[0] + Float(index) * 137.508).truncatingRemainder(dividingBy: 360)
    }

    /// A structural node's fill. Content nodes never come here: they are painted
    /// from their score by `scoreNodeColor`, and fall back to `unlearnedFill`
    /// before any user state exists.
    static func nodeColor(hue: Float, tier: LODTier, theme: Theme) -> UInt32 {
        tier <= .subbranch
            ? theme.structuralFill(tier: tier).packed
            : theme.unlearnedFill.packed
    }

    static func labelColor(tier: LODTier, theme: Theme) -> UInt32 {
        theme.labelColor(tier: tier).packed
    }

    /// Edge endpoint colour.
    ///
    /// The redesign makes edges monochrome: two tones, one for the `contains`
    /// filaments and one for everything that carries meaning between content
    /// nodes. Phase 6's per-endpoint score inheritance is gone deliberately — with
    /// hue now encoding branch, coloured edges put a third colour system on a
    /// canvas that already has two, and the design's note is explicit that the map
    /// should "let the map carry the colour" through its nodes.
    ///
    /// `weight` survives as a pure intensity: a `contains` filament is still
    /// bright at the hub and faded at the child, which is what makes galaxies.
    static func edgeColor(_ edgeClass: GraphScene.EdgeClass, weight: Float, theme: Theme) -> UInt32
    {
        let tone = edgeClass == .contains ? theme.edgeDim : theme.edgeLit
        return tone.withAlpha(Double(weight)).packed
    }

    // MARK: - §4.5 score colours

    /// A content node's fill at ramp position `t`, in its branch's hue.
    ///
    /// No tier attenuation, and that is a change: Phase 6 dimmed lower tiers so LOD
    /// depth survived the hue ramp, but under a luminance encoding dimming *is* the
    /// score. A detail node and a landmark node that are equally well known now
    /// render as the same colour, and depth comes from size alone.
    static func scoreNodeColor(rampT: Double?, hue: Float, theme: Theme) -> UInt32 {
        theme.nodeFill(rampT: rampT, hue: hue).packed
    }

    /// A `relates` edge that carries its own FSRS state (§4.4: "edge scores render
    /// as the edge's color intensity"). The redesign's monochrome tone is kept and
    /// the score moves the alpha, which is exactly what §4.4 asks for and what a
    /// second hue system would have obscured.
    static func scoreEdgeColor(rampT: Double, weight: Float, theme: Theme) -> UInt32 {
        theme.edgeLit.withAlpha(Double(weight) * (0.45 + 0.55 * min(max(rampT, 0), 1))).packed
    }

    static func frontierRingColor(theme: Theme) -> UInt32 { theme.frontierRing.packed }
    static func hoverRingColor(theme: Theme) -> UInt32 { theme.hoverRing.packed }
    /// Prerequisites of the hovered node — what it is built on.
    static func prerequisiteRingColor(theme: Theme) -> UInt32 { theme.prerequisiteRing.packed }
    /// Dependents — what is built on it.
    static func dependentRingColor(theme: Theme) -> UInt32 { theme.dependentRing.packed }
    static func highlightEdgeColor(theme: Theme) -> UInt32 { theme.highlightEdge.packed }

    static func hsv(_ hueDegrees: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let h = (hueDegrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let rgb: SIMD3<Float>
        switch Int(h) {
        case 0: rgb = SIMD3(c, x, 0)
        case 1: rgb = SIMD3(x, c, 0)
        case 2: rgb = SIMD3(0, c, x)
        case 3: rgb = SIMD3(0, x, c)
        case 4: rgb = SIMD3(x, 0, c)
        default: rgb = SIMD3(c, 0, x)
        }
        return rgb + SIMD3(repeating: m)
    }
}
