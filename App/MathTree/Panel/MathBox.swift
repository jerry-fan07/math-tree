import AppKit
import SwiftUI

/// Geometry for `MathText.Box`: the part of maths typesetting a baseline shift cannot do.
///
/// `MathText` decides *what* nests in what; this file owns every point of *where*. A
/// construct is measured from its baseline — a width, an ascent and a descent — and then
/// drawn into an `NSImage` the size of that box, which the caller inlines into a line of
/// text with `.baselineOffset(-descent)`.
///
/// Three things are worth knowing before changing any number in here:
///
/// - **One construct per image, never a whole span.** `$\frac{a}{b} + \frac{c}{d}$` becomes
///   two images with live, breakable text between them. Rasterising the span instead would
///   turn every formula into one unbreakable glyph, and the panel is 360 points wide.
/// - **Everything is a multiple of `em`**, the point size the construct sits at, so a
///   fraction in a superscript in a lesson card is the same shape as one in a panel title
///   at half the size.
/// - **The maths axis, not the baseline, is the centre of the notation.** A fraction rule, a
///   binomial's midpoint and a stretched parenthesis all centre on `font.xHeight / 2` above
///   the baseline. That is why `$\frac{1}{2} + \frac{3}{4}$` has its two rules on one line
///   and why the `+` sits between them rather than under them.
enum MathBox {

    /// A laid-out fragment, measured from its own baseline. Both extents are non-negative.
    struct Metrics: Equatable {
        var width: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0

        var height: CGFloat { ascent + descent }
    }

    /// Everything the caller's type scale contributes. Hashable because it is half of the
    /// image cache's key.
    struct Style: Hashable {
        var baseSize: CGFloat
        var weight: CGFloat = NSFont.Weight.regular.rawValue
        /// The face for non-maths runs. Maths is always the serif — that is what makes a
        /// variable read as a variable — so this only reaches `\text{…}`-free prose, which
        /// never appears inside a box.
        var proseIsSerif: Bool = false

        var fontWeight: NSFont.Weight { NSFont.Weight(weight) }
    }

    /// A drawn construct and where its baseline sits inside it.
    struct Rendered {
        var image: NSImage
        /// How far the image hangs below the text baseline — the number the caller passes
        /// to `.baselineOffset(_:)`, negated.
        var descent: CGFloat
    }

    // MARK: - Entry point

    /// Draw one box run. Returns `nil` for a run that carries no box.
    @MainActor
    static func rendered(_ run: MathText.Run, style: Style) -> Rendered? {
        guard let box = run.box else { return nil }
        let key = CacheKey(box: box, size: run.sizeMultiplier, style: style)
        if let hit = cache[key] { return hit }
        let em = max(style.baseSize * run.sizeMultiplier, 5)
        let metrics = measure(box, em: em, style: style)
        guard metrics.width > 0, metrics.height > 0 else { return nil }

        let image = NSImage(
            size: CGSize(width: ceil(metrics.width), height: ceil(metrics.height)),
            flipped: false
        ) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.setFillColor(NSColor.black.cgColor)
            draw(box, em: em, style: style, baseline: CGPoint(x: 0, y: metrics.descent),
                in: context)
            return true
        }
        // Template, so `foregroundStyle` tints it: a construct has to take the colour of
        // the line it sits in — muted in a summary, the warning tint in a wrong answer —
        // and baking the colour in would need one image per colour per theme.
        image.isTemplate = true

        let result = Rendered(image: image, descent: metrics.descent)
        if cache.count > 512 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private struct CacheKey: Hashable {
        var box: MathText.Box
        var size: Double
        var style: Style
    }

    /// Bodies re-evaluate constantly and every one of them would otherwise re-measure and
    /// re-rasterise every fraction on screen. Main-actor isolated, which is where SwiftUI
    /// builds its views; the drawing handler itself touches nothing shared.
    @MainActor private static var cache: [CacheKey: Rendered] = [:]

    // MARK: - Runs

    /// The horizontal layout every box is built from: runs side by side, each on its own
    /// baseline shift, measured together from the shared baseline.
    static func measure(_ runs: [MathText.Run], style: Style) -> Metrics {
        var metrics = Metrics()
        for run in runs {
            let shift = style.baseSize * run.baselineMultiplier
            let part: Metrics
            if run.box != nil {
                part = measure(
                    run.box!, em: max(style.baseSize * run.sizeMultiplier, 5), style: style)
            } else {
                part = measure(text: run, style: style)
            }
            metrics.width += part.width
            metrics.ascent = max(metrics.ascent, part.ascent + shift)
            metrics.descent = max(metrics.descent, part.descent - shift)
        }
        return metrics
    }

    static func draw(
        _ runs: [MathText.Run], style: Style, baseline: CGPoint, in context: CGContext
    ) {
        var x = baseline.x
        for run in runs {
            let shift = style.baseSize * run.baselineMultiplier
            let origin = CGPoint(x: x, y: baseline.y + shift)
            if let box = run.box {
                let em = max(style.baseSize * run.sizeMultiplier, 5)
                draw(box, em: em, style: style, baseline: origin, in: context)
                x += measure(box, em: em, style: style).width
            } else {
                let line = ctLine(run, style: style)
                context.textPosition = origin
                CTLineDraw(line, context)
                x += advance(of: line)
            }
        }
    }

    /// Glyph extents rather than font metrics, deliberately.
    ///
    /// A fraction's parts are placed by clearance from the rule, so `\frac{1}{2}` should sit
    /// tighter than `\frac{p}{q}` — the descender is what pushes the numerator up, and with
    /// font-metric descents every fraction would reserve room for a descender it does not
    /// have. Empty and whitespace-only runs measure to nothing but keep their advance.
    private static func measure(text run: MathText.Run, style: Style) -> Metrics {
        let line = ctLine(run, style: style)
        let width = advance(of: line)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard !bounds.isNull, bounds.height > 0 else { return Metrics(width: width) }
        return Metrics(
            width: width, ascent: max(bounds.maxY, 0), descent: max(-bounds.minY, 0))
    }

    // MARK: - Boxes

    private static func measure(_ box: MathText.Box, em: CGFloat, style: Style) -> Metrics {
        switch box {
        case let .fraction(numerator, denominator):
            return stack(numerator, denominator, em: em, style: style, rule: true).metrics
        case let .binomial(top, bottom):
            let inner = stack(top, bottom, em: em, style: style, rule: false).metrics
            let paren = parenthesisWidth(inner, em: em, style: style)
            return Metrics(
                width: inner.width + 2 * paren, ascent: inner.ascent, descent: inner.descent)
        case let .radical(degree, radicand):
            return radical(degree, radicand, em: em, style: style).metrics
        case let .rule(over, content):
            return ruled(content, over: over, em: em, style: style).metrics
        case let .accent(mark, content, isWide):
            return accented(mark, content, isWide: isWide, em: em, style: style).metrics
        case let .delimited(open, content, close):
            return delimited(open, content, close, em: em, style: style).metrics
        }
    }

    private static func draw(
        _ box: MathText.Box, em: CGFloat, style: Style, baseline: CGPoint, in context: CGContext
    ) {
        switch box {
        case let .fraction(numerator, denominator):
            let laid = stack(numerator, denominator, em: em, style: style, rule: true)
            drawStack(
                laid, numerator, denominator, em: em, style: style, baseline: baseline,
                in: context, inset: 0)
            context.fill(
                CGRect(
                    x: baseline.x, y: baseline.y + laid.ruleBottom, width: laid.metrics.width,
                    height: laid.ruleThickness))

        case let .binomial(top, bottom):
            let laid = stack(top, bottom, em: em, style: style, rule: false)
            let paren = parenthesisWidth(laid.metrics, em: em, style: style)
            drawStack(
                laid, top, bottom, em: em, style: style, baseline: baseline, in: context,
                inset: paren)
            let full = CGRect(
                x: baseline.x, y: baseline.y - laid.metrics.descent,
                width: laid.metrics.width + 2 * paren, height: laid.metrics.height)
            drawDelimiter("(", in: CGRect(x: full.minX, y: full.minY, width: paren,
                height: full.height), em: em, style: style, in: context)
            drawDelimiter(")", in: CGRect(x: full.maxX - paren, y: full.minY, width: paren,
                height: full.height), em: em, style: style, in: context)

        case let .radical(degree, radicand):
            drawRadical(degree, radicand, em: em, style: style, baseline: baseline, in: context)

        case let .rule(over, content):
            let laid = ruled(content, over: over, em: em, style: style)
            draw(content, style: style, baseline: baseline, in: context)
            context.fill(
                CGRect(
                    x: baseline.x, y: baseline.y + laid.ruleBottom, width: laid.metrics.width,
                    height: laid.thickness))

        case let .accent(mark, content, isWide):
            let laid = accented(mark, content, isWide: isWide, em: em, style: style)
            draw(
                content, style: style,
                baseline: CGPoint(x: baseline.x + laid.contentOffset, y: baseline.y),
                in: context)
            drawAccent(
                mark,
                in: CGRect(
                    x: baseline.x + laid.markOrigin.x, y: baseline.y + laid.markOrigin.y,
                    width: laid.markSize.width, height: laid.markSize.height),
                em: em, in: context)

        case let .delimited(open, content, close):
            let laid = delimited(open, content, close, em: em, style: style)
            let bottom = baseline.y + laid.bottom
            if !open.isEmpty {
                drawDelimiter(
                    open,
                    in: CGRect(
                        x: baseline.x, y: bottom, width: laid.openWidth, height: laid.height),
                    em: em, style: style, in: context)
            }
            draw(
                content, style: style,
                baseline: CGPoint(x: baseline.x + laid.openWidth, y: baseline.y), in: context)
            if !close.isEmpty {
                drawDelimiter(
                    close,
                    in: CGRect(
                        x: baseline.x + laid.metrics.width - laid.closeWidth, y: bottom,
                        width: laid.closeWidth, height: laid.height),
                    em: em, style: style, in: context)
            }
        }
    }

    // MARK: - Paired delimiters

    private struct Delimited {
        var metrics = Metrics()
        var openWidth: CGFloat = 0
        var closeWidth: CGFloat = 0
        var height: CGFloat = 0
        /// Where the delimiters start, relative to the enclosing baseline.
        var bottom: CGFloat = 0
    }

    /// Brackets grown to what they hold.
    ///
    /// TeX grows a delimiter *symmetrically about the maths axis*, never about the
    /// baseline: whichever side of the axis the content reaches further, both sides match
    /// it. That is why `\left(\frac{a}{b}\right)` has equal bracket above and below the
    /// rule, and why the same brackets around `x^2` — which reaches up and not down — are
    /// still centred rather than sitting on the baseline.
    private static func delimited(
        _ open: String, _ content: [MathText.Run], _ close: String, em: CGFloat, style: Style
    ) -> Delimited {
        let inner = measure(content, style: style)
        let axis = axisHeight(em: em, style: style)
        let reach = max(inner.ascent - axis, inner.descent + axis)
        let half = max(reach + em * 0.08, em * 0.38)

        var laid = Delimited()
        laid.height = 2 * half
        laid.bottom = axis - half
        laid.openWidth = width(ofDelimiter: open, height: laid.height, em: em, style: style)
        laid.closeWidth = width(ofDelimiter: close, height: laid.height, em: em, style: style)
        laid.metrics = Metrics(
            width: laid.openWidth + inner.width + laid.closeWidth,
            ascent: max(inner.ascent, axis + half),
            descent: max(inner.descent, half - axis))
        return laid
    }

    private static func width(
        ofDelimiter text: String, height: CGFloat, em: CGFloat, style: Style
    ) -> CGFloat {
        guard let character = text.first else { return 0 }
        let font = Typeface.nsSerif(em, style.fontWeight)
        guard let path = glyphPath(character, font: font) else { return em * 0.28 }
        let bounds = path.boundingBoxOfPath
        guard bounds.height > 0, bounds.width > 0 else { return em * 0.28 }
        return bounds.width * horizontalScale(for: height / bounds.height) + em * 0.07
    }

    /// How much a stretched delimiter widens. Damped hard: a parenthesis grown to twice
    /// its height and twice its width is a different letterform, not a bigger bracket.
    private static func horizontalScale(for verticalScale: CGFloat) -> CGFloat {
        min(verticalScale, 1 + (verticalScale - 1) * 0.28)
    }

    // MARK: - Stacks

    /// One thing over another: the shape behind both `\frac` and `\binom`.
    private struct Stack {
        var metrics = Metrics()
        var topBaseline: CGFloat = 0
        var bottomBaseline: CGFloat = 0
        var topOffset: CGFloat = 0
        var bottomOffset: CGFloat = 0
        var ruleBottom: CGFloat = 0
        var ruleThickness: CGFloat = 0
    }

    private static func stack(
        _ top: [MathText.Run], _ bottom: [MathText.Run], em: CGFloat, style: Style, rule: Bool
    ) -> Stack {
        let topMetrics = measure(top, style: style)
        let bottomMetrics = measure(bottom, style: style)
        let axis = axisHeight(em: em, style: style)
        let thickness = ruleThickness(em: em)
        // The clearance between a part's nearest edge and the rule. TeX's text-style
        // minimum is one rule thickness; this is nearer three, because the corpus's
        // fractions sit inside running prose where a tight one reads as a smudge.
        let gap = max(thickness * 2.6, em * 0.11)
        let half = rule ? thickness / 2 : em * 0.06

        var laid = Stack()
        laid.ruleThickness = thickness
        laid.ruleBottom = axis - thickness / 2
        laid.topBaseline = axis + half + gap + topMetrics.descent
        laid.bottomBaseline = axis - half - gap - bottomMetrics.ascent

        let pad = em * 0.10
        let width = max(topMetrics.width, bottomMetrics.width) + 2 * pad
        laid.topOffset = (width - topMetrics.width) / 2
        laid.bottomOffset = (width - bottomMetrics.width) / 2
        laid.metrics = Metrics(
            width: width,
            ascent: laid.topBaseline + topMetrics.ascent,
            descent: bottomMetrics.descent - laid.bottomBaseline)
        return laid
    }

    private static func drawStack(
        _ laid: Stack, _ top: [MathText.Run], _ bottom: [MathText.Run], em: CGFloat,
        style: Style, baseline: CGPoint, in context: CGContext, inset: CGFloat
    ) {
        draw(
            top, style: style,
            baseline: CGPoint(
                x: baseline.x + inset + laid.topOffset, y: baseline.y + laid.topBaseline),
            in: context)
        draw(
            bottom, style: style,
            baseline: CGPoint(
                x: baseline.x + inset + laid.bottomOffset, y: baseline.y + laid.bottomBaseline),
            in: context)
    }

    // MARK: - Radical

    private struct Radical {
        var metrics = Metrics()
        var signWidth: CGFloat = 0
        var barTop: CGFloat = 0
        var thickness: CGFloat = 0
        var bottom: CGFloat = 0
        var contentMetrics = Metrics()
        var degreeMetrics = Metrics()
        var degreeBaseline: CGFloat = 0
        var lead: CGFloat = 0
    }

    private static func radical(
        _ degree: [MathText.Run], _ radicand: [MathText.Run], em: CGFloat, style: Style
    ) -> Radical {
        let content = measure(radicand, style: style)
        let degreeMetrics = degree.isEmpty ? Metrics() : measure(degree, style: style)
        let thickness = ruleThickness(em: em)
        // The radicand must clear the vinculum, and the sign must reach below whatever
        // hangs off the radicand — a `\sqrt{\frac{a}{b}}` is most of a line tall.
        let clearance = max(thickness * 2.2, em * 0.10)
        var laid = Radical()
        laid.thickness = thickness
        laid.contentMetrics = content
        laid.degreeMetrics = degreeMetrics
        laid.barTop = max(content.ascent, xHeight(em: em, style: style)) + clearance + thickness
        laid.bottom = -content.descent - em * 0.06
        // Wider as it grows taller: a hook drawn at a fixed width under a two-line
        // radicand reads as a tick mark rather than a radical.
        let height = laid.barTop - laid.bottom
        laid.signWidth = min(max(em * 0.46, height * 0.30), em * 0.95)
        laid.lead = radicalLead(laid.signWidth, degree: degreeMetrics)
        laid.degreeBaseline = laid.bottom + height * 0.52
        laid.metrics = Metrics(
            width: laid.lead + laid.signWidth + content.width + em * 0.14,
            ascent: max(laid.barTop, laid.degreeBaseline + degreeMetrics.ascent),
            descent: -laid.bottom)
        return laid
    }

    private static func drawRadical(
        _ degree: [MathText.Run], _ radicand: [MathText.Run], em: CGFloat, style: Style,
        baseline: CGPoint, in context: CGContext
    ) {
        let laid = radical(degree, radicand, em: em, style: style)
        let signRect = CGRect(
            x: baseline.x + laid.lead, y: baseline.y + laid.bottom, width: laid.signWidth,
            height: laid.barTop - laid.bottom)
        drawRadicalSign(in: signRect, thickness: laid.thickness, in: context)
        context.fill(
            CGRect(
                x: signRect.maxX - laid.thickness * 0.4,
                y: baseline.y + laid.barTop - laid.thickness,
                width: laid.contentMetrics.width + em * 0.14 + laid.thickness * 0.4,
                height: laid.thickness))
        draw(
            radicand, style: style,
            baseline: CGPoint(x: signRect.maxX + em * 0.07, y: baseline.y), in: context)
        if !degree.isEmpty {
            // The index sits in the crook of the hook: its *right* edge against the knee
            // of the descending stroke, a little above the radical's midpoint. Anchoring
            // its left edge instead — which is the obvious thing to write — draws a wide
            // index straight through the stroke it is supposed to nestle against.
            draw(
                degree, style: style,
                baseline: CGPoint(
                    x: signRect.minX + laid.signWidth * radicalKnee
                        - laid.degreeMetrics.width,
                    y: baseline.y + laid.degreeBaseline),
                in: context)
        }
    }

    /// The knee of the radical, as a fraction of its width — where the light entry
    /// stroke meets the heavy descending one, and where an index tucks in.
    private static let radicalKnee: CGFloat = 0.34

    private static func radicalLead(_ signWidth: CGFloat, degree: Metrics) -> CGFloat {
        max(degree.width - signWidth * radicalKnee, 0)
    }

    /// The radical sign, as a filled outline rather than a stretched glyph.
    ///
    /// A `√` scaled to twice its height — which is what a fraction under a root needs —
    /// stretches its stroke weights with it and stops matching the rule it joins. Four
    /// points and a thickness do not.
    private static func drawRadicalSign(
        in rect: CGRect, thickness: CGFloat, in context: CGContext
    ) {
        let kneeX = rect.minX + rect.width * radicalKnee
        let kneeY = rect.minY + rect.height * 0.30
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: kneeY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: kneeX, y: kneeY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - thickness / 2))
        context.saveGState()
        context.addPath(path)
        context.setLineWidth(thickness * 1.15)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
        // The descending stroke of a radical is the heavy one in every maths face; a
        // second pass over it alone is the cheapest way to keep that contrast.
        context.move(to: CGPoint(x: kneeX, y: kneeY))
        context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY))
        context.setLineWidth(thickness * 2.1)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Rules and accents

    private struct Ruled {
        var metrics = Metrics()
        var ruleBottom: CGFloat = 0
        var thickness: CGFloat = 0
    }

    private static func ruled(
        _ content: [MathText.Run], over: Bool, em: CGFloat, style: Style
    ) -> Ruled {
        let inner = measure(content, style: style)
        let thickness = ruleThickness(em: em)
        let gap = max(thickness * 2.2, em * 0.10)
        var laid = Ruled()
        laid.thickness = thickness
        if over {
            let top = max(inner.ascent, xHeight(em: em, style: style)) + gap + thickness
            laid.ruleBottom = top - thickness
            laid.metrics = Metrics(width: inner.width, ascent: top, descent: inner.descent)
        } else {
            laid.ruleBottom = -inner.descent - gap - thickness
            laid.metrics = Metrics(
                width: inner.width, ascent: inner.ascent,
                descent: inner.descent + gap + thickness)
        }
        return laid
    }

    private struct Accented {
        var metrics = Metrics()
        var contentOffset: CGFloat = 0
        var markOrigin: CGPoint = .zero
        var markSize: CGSize = .zero
    }

    private static func accented(
        _ mark: MathText.Accent, _ content: [MathText.Run], isWide: Bool, em: CGFloat,
        style: Style
    ) -> Accented {
        let inner = measure(content, style: style)
        let height = accentHeight(mark, em: em)
        // A narrow accent is centred over the nucleus at its own width; a wide one
        // spans it. That is the whole difference between `\hat{x}` and `\widehat{xy}`.
        let width =
            isWide
            ? max(inner.width * 0.94, em * 0.32)
            : min(max(inner.width * 0.8, em * 0.26), em * 0.52)
        let gap = em * (mark == .bar ? 0.075 : 0.055)
        let bottom = max(inner.ascent, xHeight(em: em, style: style)) + gap

        var laid = Accented()
        laid.metrics = Metrics(
            width: max(inner.width, width), ascent: bottom + height, descent: inner.descent)
        laid.contentOffset = (laid.metrics.width - inner.width) / 2
        laid.markOrigin = CGPoint(x: (laid.metrics.width - width) / 2, y: bottom)
        laid.markSize = CGSize(width: width, height: height)
        return laid
    }

    /// How tall each mark is drawn, in ems.
    ///
    /// The shaped marks need real height or they collapse into the bar. At body size an
    /// `em * 0.11` tilde is under two points tall and drawn with a one-point stroke, which
    /// is a dash: `\tilde{f}` and `\bar{f}` came out identical, and so did `\vec{v}`,
    /// whose arrowhead was three quarters of a point wide. A mark has to be tall enough
    /// for its shape to survive the stroke that draws it.
    private static func accentHeight(_ mark: MathText.Accent, em: CGFloat) -> CGFloat {
        switch mark {
        case .bar: return max(ruleThickness(em: em), em * 0.05)
        case .dot, .doubleDot: return em * 0.085
        case .hat, .check: return em * 0.16
        case .tilde: return em * 0.17
        case .vector: return em * 0.20
        case .breve: return em * 0.13
        case .acute, .grave: return em * 0.14
        }
    }

    /// The marks, drawn rather than typed.
    ///
    /// Combining characters were the previous answer and they are the one construct the
    /// Phase 4 render verification caught outright: a face that has no precomposed `x̂`
    /// draws the mark at the following character's advance, so `\hat{p}_i` came out with
    /// the circumflex over the subscript. A path cannot land anywhere but where it is put.
    private static func drawAccent(
        _ mark: MathText.Accent, in rect: CGRect, em: CGFloat, in context: CGContext
    ) {
        let thickness = max(ruleThickness(em: em) * 1.15, 0.7)
        context.saveGState()
        context.setLineWidth(thickness)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch mark {
        case .bar:
            context.fill(
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
        case .dot:
            context.fillEllipse(
                in: CGRect(
                    x: rect.midX - rect.height / 2, y: rect.minY, width: rect.height,
                    height: rect.height))
        case .doubleDot:
            let d = rect.height
            context.fillEllipse(
                in: CGRect(x: rect.midX - d * 1.15, y: rect.minY, width: d, height: d))
            context.fillEllipse(
                in: CGRect(x: rect.midX + d * 0.15, y: rect.minY, width: d, height: d))
        case .hat:
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.strokePath()
        case .check:
            context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.strokePath()
        case .tilde:
            // One S, drawn across the full height it was given: up over the first half,
            // down over the second, with the inflection at the midpoint.
            context.move(to: CGPoint(x: rect.minX, y: rect.minY + thickness / 2))
            context.addCurve(
                to: CGPoint(x: rect.midX, y: rect.midY),
                control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY),
                control2: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.maxY))
            context.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - thickness / 2),
                control1: CGPoint(x: rect.midX + rect.width * 0.10, y: rect.minY),
                control2: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.minY))
            context.strokePath()
        case .breve:
            context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.5))
            context.strokePath()
        case .acute:
            context.move(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY))
            context.strokePath()
        case .grave:
            context.move(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
            context.strokePath()
        case .vector:
            // The head is sized off the *width* it has to fit in, not off the accent's
            // height: an arrowhead scaled from a two-point mark is a rounding error, and
            // an arrow without a visible head is a macron.
            let head = min(rect.width * 0.42, rect.height * 0.85)
            let shaft = rect.midY
            context.move(to: CGPoint(x: rect.minX, y: shaft))
            context.addLine(to: CGPoint(x: rect.maxX - thickness / 2, y: shaft))
            context.strokePath()
            context.move(to: CGPoint(x: rect.maxX - head, y: shaft + head * 0.52))
            context.addLine(to: CGPoint(x: rect.maxX, y: shaft))
            context.addLine(to: CGPoint(x: rect.maxX - head, y: shaft - head * 0.52))
            context.setLineWidth(thickness * 0.85)
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Delimiters

    private static func parenthesisWidth(_ inner: Metrics, em: CGFloat, style: Style)
        -> CGFloat
    {
        max(em * 0.26, min(inner.height * 0.20, em * 0.42))
    }

    /// A delimiter stretched to the height it encloses.
    ///
    /// Scaled from the face's own outline, not drawn: a parenthesis is a shape with a
    /// weight distribution, and an approximation of one next to a real one — the corpus
    /// writes both — is immediately visible. The horizontal scale is deliberately damped,
    /// which is what keeps a tall delimiter from also becoming a fat one.
    private static func drawDelimiter(
        _ text: String, in rect: CGRect, em: CGFloat, style: Style, in context: CGContext
    ) {
        let font = Typeface.nsSerif(em, style.fontWeight)
        guard let character = text.first, let path = glyphPath(character, font: font) else {
            return
        }
        let bounds = path.boundingBoxOfPath
        guard bounds.height > 0, bounds.width > 0 else { return }
        let scaleY = rect.height / bounds.height
        let scaleX = horizontalScale(for: scaleY)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.minY)
            .scaledBy(x: scaleX, y: scaleY)
            .translatedBy(x: -bounds.midX, y: -bounds.minY)
        guard let scaled = path.copy(using: &transform) else { return }
        context.addPath(scaled)
        context.fillPath()
    }

    private static func glyphPath(_ character: Character, font: NSFont) -> CGPath? {
        var utf16 = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count),
            let first = glyphs.first
        else { return nil }
        return CTFontCreatePathForGlyph(font, first, nil)
    }

    // MARK: - Metrics of the face

    /// Where the notation centres. Everything symmetric — a fraction rule, a binomial's
    /// midpoint, a stretched delimiter — hangs off this one number.
    private static func axisHeight(em: CGFloat, style: Style) -> CGFloat {
        xHeight(em: em, style: style) / 2
    }

    private static func xHeight(em: CGFloat, style: Style) -> CGFloat {
        Typeface.nsSerif(em, style.fontWeight).xHeight
    }

    private static func ruleThickness(em: CGFloat) -> CGFloat {
        max(em * 0.045, 0.7)
    }

    // MARK: - Core Text

    static func font(for run: MathText.Run, style: Style) -> NSFont {
        let size = max(style.baseSize * run.sizeMultiplier, 6)
        let base =
            (run.isMath || style.proseIsSerif)
            ? Typeface.nsSerif(size, style.fontWeight)
            : Typeface.nsSans(size, style.fontWeight)
        return run.isItalic ? Typeface.nsItalic(base) : base
    }

    private static func ctLine(_ run: MathText.Run, style: Style) -> CTLine {
        let attributed = NSAttributedString(
            string: run.text,
            attributes: [
                .font: font(for: run, style: style),
                .foregroundColor: NSColor.black,
            ])
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func advance(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
