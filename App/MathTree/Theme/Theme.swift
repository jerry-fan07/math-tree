import SwiftUI
import simd

/// One colour, in straight (non-premultiplied) sRGB on 0…1, in whichever shape
/// the caller needs it.
///
/// The map and the chrome are drawn by two different systems — packed rgba8 words
/// into a Metal instance buffer, and SwiftUI `Color`s — and the redesign gives
/// them the same palette. Carrying one type that converts both ways is what keeps
/// a rail dot and the node it points at from drifting apart.
struct ThemeColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `rgba(238, 242, 250, 0.94)` as the design writes it — 8-bit components, so
    /// the values in the source read as the values in the design document.
    static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1)
        -> ThemeColor
    {
        ThemeColor(red / 255, green / 255, blue / 255, alpha)
    }

    /// `oklch(L C H)` / `oklch(L C H / a)`, resolved through `OKLCH`.
    static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double, _ alpha: Double = 1)
        -> ThemeColor
    {
        let rgb = OKLCH.srgb(lightness, chroma, hue)
        return ThemeColor(rgb.x, rgb.y, rgb.z, alpha)
    }

    var packed: UInt32 {
        packRGBA(Float(red), Float(green), Float(blue), Float(alpha))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var simd4: SIMD4<Double> { SIMD4(red, green, blue, alpha) }

    func withAlpha(_ alpha: Double) -> ThemeColor {
        ThemeColor(red, green, blue, alpha)
    }

    /// Alpha scaled rather than replaced — for the places where a base tone is
    /// already carrying an intensity the caller wants to attenuate further.
    func fading(_ factor: Double) -> ThemeColor {
        ThemeColor(red, green, blue, alpha * factor)
    }
}

/// The two directions of the turn-1 redesign, as one switch.
///
/// `dark` is **Observatory**: hue per branch on a near-black canvas, score read
/// as luminance — a solid node glows, a decayed one sinks toward the background.
/// `light` is **Ledger**: the same hue per branch on paper, score read as ink
/// density — a solid node is dense and dark, a decayed one is washed out. They
/// are the same layout and the same encoding, inverted; that is why one `Theme`
/// serves both instead of two view hierarchies.
enum Appearance: String, CaseIterable, Sendable {
    case dark
    case light

    /// `MATHTREE_THEME=light|dark` pins the appearance. Present because the
    /// snapshot and probe paths never open a window and so have no system
    /// appearance to follow — and because a pinned theme is what makes the two
    /// design frames reproducible side by side.
    static func override(in environment: [String: String]) -> Appearance? {
        environment["MATHTREE_THEME"].flatMap { Appearance(rawValue: $0.lowercased()) }
    }
}

/// Every colour and metric the redesign specifies, resolved for one appearance.
///
/// Deliberately a flat bag of literals rather than a generated ramp: the design
/// document names each value, and a token whose provenance is "the design says
/// this" is easier to keep faithful than one derived from three others. The two
/// instances live side by side at the bottom of this file so a dark value and its
/// light counterpart are read together.
struct Theme: Sendable {
    let appearance: Appearance

    // MARK: - Canvas (§6.1)

    /// Radial gradient centre and edge. In `light` both are the same paper colour,
    /// which is the design's flat `#F6F5F2` — the background pass then draws a
    /// constant and costs one fullscreen triangle.
    let canvasCore: ThemeColor
    let canvasEdge: ThemeColor

    /// Structural fills, by tier. §2.1's hubs are not learnable, so they never
    /// take a score colour; the redesign pushes them to near-neutral so the branch
    /// hues belong entirely to the content nodes.
    let branchFill: ThemeColor
    let subbranchFill: ThemeColor

    /// §4.5's "neutral gray, low opacity — visually recedes".
    let unlearnedFill: ThemeColor

    /// Lightness and chroma at the two ends of the score ramp. The hue is the
    /// node's branch hue and never moves: that is the encoding change this
    /// redesign makes — hue says *where in mathematics*, luminance says *how well
    /// you know it*. In `light` the lightness runs downward (dense ink = solid).
    let contentLightness: (decayed: Double, solid: Double)
    let contentChroma: (decayed: Double, solid: Double)

    /// The two edge tones of the design: `dim` carries the `contains` filaments
    /// that make branches read as galaxies, `lit` carries `requires` and `relates`.
    let edgeDim: ThemeColor
    let edgeLit: ThemeColor
    /// Multiplies every class's band-mixed alpha. The redesign's hairlines are
    /// much fainter than Phase 4's; keeping the per-class ramp and scaling it here
    /// preserves §6.1's "contains dominates at overview, requires takes over by
    /// mid zoom" instead of re-deriving it.
    let edgeIntensity: Float

    /// §4.5's frontier accent — warm, and from outside the score encoding so it
    /// can never be read as a retrievability value.
    let frontierRing: ThemeColor
    let hoverRing: ThemeColor
    let prerequisiteRing: ThemeColor
    let dependentRing: ThemeColor
    let highlightEdge: ThemeColor

    /// Map labels. Tier 0 is uppercase mono with wide tracking in both
    /// appearances; tier 1 goes serif on paper, which is where the two directions
    /// differ most in typography.
    let branchLabel: ThemeColor
    let subbranchLabel: ThemeColor
    let contentLabel: ThemeColor

    // MARK: - Chrome

    /// The command line across the top — the first of the redesign's two surfaces.
    let barHeight: CGFloat
    let barFill: ThemeColor
    /// One hairline under the bar, one down the panel's leading edge. The redesign
    /// separates surfaces with rules, never with cards or shadows.
    let rule: ThemeColor
    /// Rules *inside* a surface, between sections — a shade quieter than `rule`.
    let hairline: ThemeColor

    let wordmark: ThemeColor
    /// Breadcrumb: the trail is quiet, the last segment is not.
    let trail: ThemeColor
    let trailCurrent: ThemeColor
    let trailSeparator: ThemeColor
    let stat: ThemeColor
    let statEmphasis: ThemeColor

    /// The review rail. A scrim rather than a panel: it fades out over the map on
    /// its trailing edge instead of ending in a border, so the map reads as one
    /// continuous surface running underneath.
    let railWidth: CGFloat
    let railScrimNear: ThemeColor
    let railScrimFar: ThemeColor

    /// The detail column — the redesign's second surface, and the only one that is
    /// fully opaque.
    let panelWidth: CGFloat
    let panelFill: ThemeColor

    /// Section eyebrows: mono, uppercase, wide-tracked, quiet.
    let eyebrow: ThemeColor
    let eyebrowCount: ThemeColor

    /// Text ramp. `ink` is the reading weight; `inkMuted` is supporting prose;
    /// `inkFaint` is metadata that should be findable but never read first.
    let ink: ThemeColor
    let inkStrong: ThemeColor
    let inkMuted: ThemeColor
    let inkFaint: ThemeColor
    /// Row titles in the rail and the reference lists.
    let rowTitle: ThemeColor
    let rowTrailing: ThemeColor
    /// Hover feedback. The redesign has no filled row states, so this is a very
    /// light wash — enough to say "this is the row under the cursor".
    let rowHighlight: ThemeColor

    /// The one accent, used for the single affordance on each surface ("Place me",
    /// "Learn this →") as an underlined text action rather than a filled button.
    let action: ThemeColor
    /// The goal marker's rule in focus mode, and the underline weight of `action`.
    let actionRule: ThemeColor
    /// Retrievability's own colour — the solid end of the ramp at a neutral branch
    /// hue, so the number and the bar agree with the map without claiming a branch.
    let measure: ThemeColor
    let measureTrack: ThemeColor
    /// "due — review to unblock", "2 ready now": the frontier accent, in text.
    let attention: ThemeColor
    /// Reporting a miss — warm, and outside the score encoding (D6.1's rule).
    let warning: ThemeColor

    /// The score legend at the bottom right of the mid-zoom map: unlearned grey,
    /// then the ramp at three sample points.
    let scaleStops: [ThemeColor]

    /// What a modal puts over the map. Black on the dark canvas, and the paper's
    /// own ink on the light one — a 60 % black veil over `#F6F5F2` reads as a
    /// different application, not as the same page with something on top of it.
    let scrim: ThemeColor

    // MARK: - Derived

    var isDark: Bool { appearance == .dark }

    /// A content node's fill at ramp position `t` (0 = badly decayed, 1 = solid)
    /// in its branch's hue. §4.5's three states are still three states: this is
    /// the *learned* one, `unlearnedFill` is the other two.
    func contentFill(rampT t: Double, hue: Float) -> ThemeColor {
        let clamped = min(max(t, 0), 1)
        return .oklch(
            contentLightness.decayed + (contentLightness.solid - contentLightness.decayed) * clamped,
            contentChroma.decayed + (contentChroma.solid - contentChroma.decayed) * clamped,
            Double(hue))
    }

    /// The fill for a node in whichever state it is in. `nil` is §4.5's unlearned:
    /// never retrieved, or (D8.3) attempted and missed, which is not the same as
    /// "learned and badly decayed" and must not be painted like it.
    func nodeFill(rampT t: Double?, hue: Float) -> ThemeColor {
        guard let t else { return unlearnedFill }
        return contentFill(rampT: t, hue: hue)
    }

    func structuralFill(tier: LODTier) -> ThemeColor {
        tier == .branch ? branchFill : subbranchFill
    }

    func labelColor(tier: LODTier) -> ThemeColor {
        switch tier {
        case .branch: branchLabel
        case .subbranch: subbranchLabel
        default: contentLabel
        }
    }

    // MARK: - Instances

    static let observatory = Theme(
        appearance: .dark,
        // radial-gradient(115% 88% at 50% 44%, #0C0E15 0%, #07080B 72%)
        canvasCore: .rgba(12, 14, 21),
        canvasEdge: .rgba(7, 8, 11),
        branchFill: .rgba(238, 242, 250, 0.94),
        subbranchFill: .rgba(204, 213, 230, 0.60),
        unlearnedFill: .rgba(150, 158, 175, 0.26),
        contentLightness: (decayed: 0.56, solid: 0.84),
        contentChroma: (decayed: 0.095, solid: 0.170),
        edgeDim: .rgba(158, 178, 212, 1),
        edgeLit: .rgba(150, 205, 222, 1),
        edgeIntensity: 0.90,
        frontierRing: .oklch(0.84, 0.13, 82, 0.50),
        hoverRing: .rgba(255, 252, 245, 0.95),
        prerequisiteRing: .rgba(107, 199, 255, 0.85),
        dependentRing: .rgba(255, 184, 97, 0.85),
        highlightEdge: .rgba(235, 242, 255, 0.90),
        branchLabel: .rgba(238, 242, 250, 0.76),
        subbranchLabel: .rgba(238, 242, 250, 0.48),
        contentLabel: .rgba(238, 242, 250, 0.62),

        barHeight: 46,
        barFill: .rgba(7, 8, 11, 0.72),
        rule: .rgba(255, 255, 255, 0.08),
        hairline: .rgba(255, 255, 255, 0.065),
        wordmark: .rgba(238, 242, 250, 0.86),
        trail: .rgba(238, 242, 250, 0.44),
        trailCurrent: .rgba(238, 242, 250, 0.90),
        trailSeparator: .rgba(238, 242, 250, 0.24),
        stat: .rgba(238, 242, 250, 0.32),
        statEmphasis: .rgba(238, 242, 250, 0.50),

        railWidth: 252,
        railScrimNear: .rgba(7, 8, 11, 0.94),
        railScrimFar: .rgba(7, 8, 11, 0.60),

        panelWidth: 404,
        panelFill: .rgba(7, 8, 11, 0.94),

        eyebrow: .rgba(238, 242, 250, 0.40),
        eyebrowCount: .rgba(238, 242, 250, 0.26),

        ink: .rgba(242, 245, 251, 0.90),
        inkStrong: .rgba(244, 247, 253, 1.0),
        inkMuted: .rgba(238, 242, 250, 0.52),
        inkFaint: .rgba(238, 242, 250, 0.30),
        rowTitle: .rgba(238, 242, 250, 0.86),
        rowTrailing: .rgba(238, 242, 250, 0.34),
        rowHighlight: .rgba(255, 255, 255, 0.05),

        action: .oklch(0.84, 0.09, 196),
        actionRule: .oklch(0.84, 0.09, 196, 0.45),
        measure: .oklch(0.82, 0.098, 176),
        measureTrack: .rgba(255, 255, 255, 0.08),
        attention: .oklch(0.84, 0.13, 82),
        warning: .oklch(0.80, 0.11, 52),
        scaleStops: [
            .rgba(150, 158, 175, 0.28),
            .oklch(0.54, 0.085, 218),
            .oklch(0.70, 0.098, 190),
            .oklch(0.86, 0.11, 162),
        ],
        scrim: .rgba(4, 5, 8, 0.62))

    static let ledger = Theme(
        appearance: .light,
        canvasCore: .rgba(246, 245, 242),
        canvasEdge: .rgba(246, 245, 242),
        branchFill: .rgba(20, 22, 26, 0.92),
        subbranchFill: .rgba(48, 54, 64, 0.58),
        unlearnedFill: .rgba(120, 128, 144, 0.28),
        contentLightness: (decayed: 0.72, solid: 0.50),
        contentChroma: (decayed: 0.075, solid: 0.160),
        edgeDim: .rgba(20, 22, 26, 1),
        edgeLit: .rgba(40, 70, 130, 1),
        edgeIntensity: 0.80,
        frontierRing: .oklch(0.62, 0.15, 58, 0.70),
        hoverRing: .rgba(20, 22, 26, 0.95),
        prerequisiteRing: .oklch(0.52, 0.14, 252),
        dependentRing: .oklch(0.58, 0.14, 52),
        highlightEdge: .rgba(20, 22, 26, 0.55),
        branchLabel: .rgba(20, 22, 26, 0.82),
        subbranchLabel: .rgba(20, 22, 26, 0.58),
        contentLabel: .rgba(20, 22, 26, 0.70),

        barHeight: 52,
        barFill: .rgba(246, 245, 242, 0.88),
        rule: .rgba(20, 22, 26, 0.12),
        hairline: .rgba(20, 22, 26, 0.09),
        wordmark: .rgba(20, 22, 26, 1.0),
        trail: .rgba(20, 22, 26, 0.50),
        trailCurrent: .rgba(20, 22, 26, 1.0),
        trailSeparator: .rgba(20, 22, 26, 0.28),
        stat: .rgba(20, 22, 26, 0.40),
        statEmphasis: .rgba(20, 22, 26, 0.62),

        railWidth: 272,
        railScrimNear: .rgba(246, 245, 242, 0.96),
        railScrimFar: .rgba(246, 245, 242, 0.55),

        panelWidth: 412,
        panelFill: .rgba(251, 250, 248, 1.0),

        eyebrow: .rgba(20, 22, 26, 0.45),
        eyebrowCount: .rgba(20, 22, 26, 0.30),

        ink: .rgba(20, 22, 26, 1.0),
        inkStrong: .rgba(20, 22, 26, 1.0),
        inkMuted: .rgba(20, 22, 26, 0.58),
        inkFaint: .rgba(20, 22, 26, 0.40),
        rowTitle: .rgba(20, 22, 26, 1.0),
        rowTrailing: .rgba(20, 22, 26, 0.42),
        rowHighlight: .rgba(20, 22, 26, 0.045),

        action: .oklch(0.46, 0.13, 250),
        actionRule: .oklch(0.46, 0.13, 250, 0.50),
        measure: .oklch(0.48, 0.13, 158),
        measureTrack: .rgba(20, 22, 26, 0.10),
        attention: .oklch(0.56, 0.15, 58),
        warning: .oklch(0.52, 0.15, 38),
        scaleStops: [
            .rgba(120, 128, 144, 0.28),
            .oklch(0.68, 0.085, 252),
            .oklch(0.60, 0.11, 200),
            .oklch(0.50, 0.13, 158),
        ],
        scrim: .rgba(20, 22, 26, 0.34))

    static func of(_ appearance: Appearance) -> Theme {
        switch appearance {
        case .dark: observatory
        case .light: ledger
        }
    }
}

/// The one place that knows which appearance is current.
///
/// `@Observable`, so any SwiftUI body that reads `ThemeStore.shared.theme` — which
/// is every surface, through `PanelTheme` — reinvalidates when the appearance
/// changes. The map is not SwiftUI, so it is told explicitly: `onChange` calls
/// `GraphRenderer.setTheme`, which rewrites the colour words in place (no buffer
/// is rebuilt, per D3.4) and re-rasterises the label atlas, whose tier-1 face
/// differs between the two directions.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// Non-nil when `MATHTREE_THEME` pinned it. A pinned theme ignores the system
    /// appearance entirely — a snapshot run must not change with the developer's
    /// System Settings.
    let pinned: Appearance?

    private(set) var appearance: Appearance

    var theme: Theme { Theme.of(appearance) }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let pinned = Appearance.override(in: environment)
        self.pinned = pinned
        // Dark until the window says otherwise: §6.1's canvas is the dark one, and
        // a first frame that flashes paper before the system appearance arrives is
        // worse than one that never flashes.
        appearance = pinned ?? .dark
    }

    /// Follow the system, unless the environment pinned an appearance.
    func follow(_ colorScheme: ColorScheme) {
        guard pinned == nil else { return }
        let resolved: Appearance = colorScheme == .light ? .light : .dark
        guard resolved != appearance else { return }
        appearance = resolved
    }
}
