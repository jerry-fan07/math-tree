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
    /// a 9× span between a branch hub and a detail node.
    var radiiPt: (overview: Float, detail: Float) {
        switch self {
        case .branch: (17.0, 12.0)
        case .subbranch: (11.5, 9.0)
        case .landmark: (6.0, 7.5)
        case .standard: (3.6, 5.6)
        case .detail: (1.9, 4.4)
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
        case .branch: 15.0
        case .subbranch: 12.5
        case .landmark: 11.5
        case .standard: 10.5
        case .detail: 9.5
        }
    }

    /// Saturation / value applied to the node's branch hue.
    ///
    /// Structural tiers are near-white with only a cast of their branch hue, and
    /// that is a Phase 6 change: §4.5's ramp now owns the saturated blue → teal →
    /// green arc, and Phase 4's saturated hubs sat inside it — the Foundations hub
    /// (hue 152°) was indistinguishable from a mastered node. Hubs are still the
    /// centres of their galaxies through size, halo and the `contains` filaments,
    /// which keep their full hue. See D6.1.
    fileprivate var tone: (saturation: Float, value: Float, alpha: Float) {
        switch self {
        case .branch: (0.12, 1.00, 1.00)
        case .subbranch: (0.18, 0.96, 0.98)
        case .landmark: (0.64, 0.92, 0.96)
        case .standard: (0.60, 0.76, 0.92)
        case .detail: (0.52, 0.58, 0.88)
        }
    }

    /// How much of the score colour a tier keeps. Phase 4 spent value and alpha on
    /// tier depth; §4.5 now owns hue and most of the brightness, so what is left
    /// is a light attenuation — enough that a detail node still recedes behind a
    /// landmark of the same score, not enough to be mistaken for a lower score.
    /// Structural tiers never take a score colour, so their entries are unused.
    fileprivate var scoreAttenuation: (value: Float, alpha: Float) {
        switch self {
        case .branch, .subbranch: (1.00, 1.00)
        case .landmark: (1.00, 1.00)
        case .standard: (0.92, 0.96)
        case .detail: (0.84, 0.92)
        }
    }

    fileprivate var labelTone: (saturation: Float, value: Float, alpha: Float) {
        switch self {
        case .branch: (0.10, 1.00, 0.95)
        case .subbranch: (0.16, 0.98, 0.90)
        case .landmark: (0.22, 0.96, 0.86)
        case .standard: (0.20, 0.94, 0.82)
        case .detail: (0.18, 0.90, 0.76)
        }
    }
}

/// Two colour systems, split by what a node *is*.
///
/// Phase 4 gave every node a branch hue, which is what makes `contains`
/// clustering readable. Phase 6 hands §4.5 the nodes that carry a score:
/// learnable content takes the retrievability ramp (grey → deep blue → teal →
/// green) and structural hubs keep their taxonomy hue, because they are not
/// learnable (§2.1) and are the map's navigational skeleton. See D6.1.
enum Palette {
    /// Dark background of §6.1.
    static let background = SIMD4<Double>(0.043, 0.051, 0.071, 1.0)

    /// Curated first, golden-angle after. Hand-picked hues keep the first handful
    /// of branches maximally distinguishable; the generator keeps the scheme
    /// working when the corpus grows past them (§7: ~15 branches).
    private static let seedHues: [Float] = [205, 152, 38, 276, 12, 96, 320, 178, 58, 240]

    static func hue(forBranchIndex index: Int) -> Float {
        if index < seedHues.count { return seedHues[index] }
        return (seedHues[0] + Float(index) * 137.508).truncatingRemainder(dividingBy: 360)
    }

    static func nodeColor(hue: Float, tier: LODTier) -> UInt32 {
        let tone = tier.tone
        let rgb = hsv(hue, tone.saturation, tone.value)
        return packRGBA(rgb.x, rgb.y, rgb.z, tone.alpha)
    }

    static func labelColor(hue: Float, tier: LODTier) -> UInt32 {
        let tone = tier.labelTone
        let rgb = hsv(hue, tone.saturation, tone.value)
        return packRGBA(rgb.x, rgb.y, rgb.z, tone.alpha)
    }

    /// Edge endpoint colour: the node's hue, dimmed and desaturated so edges read
    /// as hairlines rather than competing with the nodes.
    static func edgeColor(hue: Float, tier: LODTier, weight: Float) -> UInt32 {
        let rgb = hsv(hue, 0.42, 0.80)
        return packRGBA(rgb.x, rgb.y, rgb.z, weight)
    }

    // MARK: - §4.5 score colours

    /// A node's score colour, attenuated for its tier so LOD depth survives the ramp.
    static func scoreNodeColor(_ color: ScoreColor, tier: LODTier) -> UInt32 {
        let attenuation = tier.scoreAttenuation
        return packRGBA(
            Float(color.red) * attenuation.value,
            Float(color.green) * attenuation.value,
            Float(color.blue) * attenuation.value,
            Float(color.alpha) * attenuation.alpha)
    }

    /// A score colour at an edge endpoint. Edges stay dimmer than the nodes they
    /// join — §6.1 wants hairlines, and an edge as bright as its endpoints would
    /// make a well-known neighbourhood read as a solid blob.
    static func scoreEdgeColor(_ color: ScoreColor, weight: Float) -> UInt32 {
        packRGBA(
            Float(color.red) * 0.86, Float(color.green) * 0.86, Float(color.blue) * 0.86,
            Float(color.alpha) * weight)
    }

    /// §4.5's frontier accent ring — "what you could learn next".
    static let frontierRingColor = packRGBA(
        Float(ScoreRamp.frontierAccent.red), Float(ScoreRamp.frontierAccent.green),
        Float(ScoreRamp.frontierAccent.blue), Float(ScoreRamp.frontierAccent.alpha))

    static let hoverRingColor = packRGBA(1.00, 0.98, 0.92, 0.95)
    /// Prerequisites of the hovered node — what it is built on.
    static let prerequisiteRingColor = packRGBA(0.42, 0.78, 1.00, 0.90)
    /// Dependents — what is built on it.
    static let dependentRingColor = packRGBA(1.00, 0.72, 0.38, 0.90)
    static let highlightEdgeColor = packRGBA(0.92, 0.95, 1.00, 1.0)

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
