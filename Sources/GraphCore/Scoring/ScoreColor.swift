import Foundation

/// A colour the score model produces, in straight (non-premultiplied) sRGB
/// components on 0…1.
///
/// Deliberately not a `CGColor`/`SIMD4` — §4.5's mapping is part of the scoring
/// model, not of the renderer, and keeping it here is what makes "relaunching
/// reproduces identical colours" testable without a GPU. The app packs these into
/// its rgba8 instance words; the probe prints them as hex.
public struct ScoreColor: Hashable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RRGGBBAA`. The stable identity of a colour for tests and the probe —
    /// comparing hex rather than floats is what keeps a determinism diff from
    /// tripping on the last bit of a `Double`.
    public var hex: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }

    public var description: String { hex }

    /// Linear blend, used for edges that inherit their endpoints' colours (§6.1).
    public static func mix(_ a: ScoreColor, _ b: ScoreColor, _ t: Double) -> ScoreColor {
        let t = min(max(t, 0), 1)
        return ScoreColor(
            red: a.red + (b.red - a.red) * t,
            green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t,
            alpha: a.alpha + (b.alpha - a.alpha) * t)
    }

    public func withAlpha(_ alpha: Double) -> ScoreColor {
        ScoreColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// §4.5's colour mapping, as a pure function of retrievability.
///
/// Three states, and the distinction between them is the whole point:
/// - **unlearned** — no FSRS state at all: neutral grey at low opacity, recedes;
/// - **learned** — a continuous cold-to-warm ramp, deep blue when badly decayed
///   through teal to green when solid, so a decayed node stays visibly *coloured*
///   (it was learned once) while a never-touched node stays grey;
/// - **frontier** — unlearned, but every prerequisite is above τ: the grey fill is
///   unchanged and an accent ring is added, because the frontier is a property of
///   the *graph around* a node rather than a score it carries.
///
/// The ramp travels in HSV so that "blue → teal → green" is a straight walk in
/// hue: interpolating in RGB would pass through a muddy desaturated midpoint
/// exactly where §4.5 wants teal to be legible.
public enum ScoreRamp {
    /// Retrievability at or below which the ramp is at its cold end — §4.5's
    /// "≈0.3, badly decayed".
    public static let decayedAnchor = 0.30
    /// Retrievability at or above which the ramp is at its warm end — §4.5's
    /// "≈0.95+, solid".
    public static let masteredAnchor = 0.95

    /// §4.5: "neutral gray, low opacity — visually recedes".
    public static let unlearned = ScoreColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 0.34)

    /// §4.5's "subtle accent ring" on frontier nodes. Deliberately warm gold: the
    /// score ramp occupies blue through green, so an accent taken from outside
    /// that arc can never be misread as a retrievability value.
    public static let frontierAccent = ScoreColor(red: 1.00, green: 0.84, blue: 0.52, alpha: 0.62)

    /// Position on the ramp, 0 at the decayed anchor and 1 at the mastered one.
    public static func rampT(forRetrievability retrievability: Double) -> Double {
        let span = masteredAnchor - decayedAnchor
        return min(max((retrievability - decayedAnchor) / span, 0), 1)
    }

    /// The colour of a *learned* node at this retrievability.
    public static func color(forRetrievability retrievability: Double) -> ScoreColor {
        let t = rampT(forRetrievability: retrievability)
        // 222° deep blue → 180° teal at the midpoint → 138° green.
        let rgb = hsv(
            hue: 222 + (138 - 222) * t,
            saturation: 0.78 + (0.70 - 0.78) * t,
            value: 0.52 + (0.95 - 0.52) * t)
        return ScoreColor(
            red: rgb.red, green: rgb.green, blue: rgb.blue,
            // Decayed nodes are dim as well as cold, but never as transparent as
            // unlearned grey — "learned and faded" must not read as "untouched".
            alpha: 0.78 + (1.00 - 0.78) * t)
    }

    /// The colour of a node in whatever state it is actually in. `nil`
    /// retrievability means no FSRS state — unlearned.
    public static func color(forRetrievability retrievability: Double?) -> ScoreColor {
        guard let retrievability else { return unlearned }
        return color(forRetrievability: retrievability)
    }

    /// The read-out the display actually uses: state + clock → colour, with
    /// retrievability computed on read (§4.1).
    public static func color(for memory: MemoryState?, at now: Date, fsrs: FSRS) -> ScoreColor {
        color(forRetrievability: memory.map { fsrs.retrievability(of: $0, at: now) })
    }

    /// The same read-out, told whether the node was ever actually learned.
    ///
    /// Phase 8 is the first thing that can write FSRS state onto a node the user
    /// has never retrieved successfully — a miss localized by §5.4's diagnosis. Its
    /// stability is a fraction of a day, so the ramp would paint it deep blue,
    /// which §4.5 reserves for "learned, badly decayed". It is not that; it is
    /// grey, and it is on the frontier (see `ScoreState.learned`).
    public static func color(
        for memory: MemoryState?, learned: Bool, at now: Date, fsrs: FSRS
    ) -> ScoreColor {
        guard learned else { return unlearned }
        return color(for: memory, at: now, fsrs: fsrs)
    }

    private static func hsv(hue: Double, saturation: Double, value: Double)
        -> (red: Double, green: Double, blue: Double)
    {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let c = value * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let rgb: (Double, Double, Double)
        switch Int(h) {
        case 0: rgb = (c, x, 0)
        case 1: rgb = (x, c, 0)
        case 2: rgb = (0, c, x)
        case 3: rgb = (0, x, c)
        case 4: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }
}
