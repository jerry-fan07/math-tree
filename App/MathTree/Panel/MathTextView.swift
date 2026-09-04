import AppKit
import SwiftUI

extension MathText {
    /// The pure conversion Phase 4 asks for: LaTeX-lite source in, styled attributed string
    /// out. No view state, no layout pass, no side effects — call it from anywhere.
    ///
    /// A run carries a font, a baseline offset and — since the two-dimensional constructs
    /// landed — possibly a drawn box, which `NSAttributedString` inlines the way it inlines
    /// any other non-text glyph: as an attachment whose bounds place its baseline.
    @MainActor
    static func attributedString(
        _ source: String,
        baseSize: CGFloat,
        weight: Font.Weight = .regular,
        mathDesign: Font.Design = .serif
    ) -> AttributedString {
        var output = AttributedString()
        let style = MathBox.Style(
            baseSize: baseSize, weight: MathTextView.nsWeight(weight).rawValue,
            proseIsSerif: mathDesign == .serif)
        for run in runs(source) {
            if run.isBox {
                guard let rendered = MathBox.rendered(run, style: style) else { continue }
                let attachment = NSTextAttachment()
                attachment.image = rendered.image
                attachment.bounds = CGRect(
                    x: 0, y: baseSize * run.baselineMultiplier - rendered.descent,
                    width: rendered.image.size.width, height: rendered.image.size.height)
                output.append(
                    AttributedString(NSAttributedString(attachment: attachment)))
                continue
            }
            var piece = AttributedString(run.text)
            var font = Font.system(
                size: max(baseSize * run.sizeMultiplier, 6),
                weight: weight,
                design: run.isMath ? mathDesign : .default)
            if run.isItalic { font = font.italic() }
            piece.font = font
            piece.baselineOffset = baseSize * run.baselineMultiplier
            output.append(piece)
        }
        return output
    }
}

/// Draws LaTeX-lite source: prose in the UI face, `$…$` spans in a serif face with variables
/// italic, super- and subscripts as shrunken baseline-shifted runs, and fractions, radicals,
/// binomials and accents as drawn boxes sitting on the line.
///
/// The glyphs are laid out by concatenating one `Text` per run rather than by handing
/// SwiftUI an `AttributedString`. Both carry identical information (see
/// `MathText.attributedString(_:baseSize:)`), but `Text.baselineOffset(_:)` is a documented
/// primitive whereas `Text`'s honouring of the *attribute* of the same name has varied
/// across OS releases — and this panel cannot be checked by eye from CI.
///
/// A box run becomes `Text(Image(…))` at that same baseline offset, less the box's own
/// descent. Per *construct*, never per span: the text between two fractions stays live text,
/// so a statement still wraps at every word it could wrap at before, and stays selectable.
struct MathTextView: View {
    /// Which face the *prose* runs take. Maths is always the serif — that is what
    /// makes a variable read as a variable. The redesign's light direction sets a
    /// node's title and its statement in the serif as well, which is the one place
    /// a caller asks for something other than the default.
    enum Face { case sans, serif }

    let source: String
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    var color: Color = PanelTheme.primaryText
    var face: Face = .sans
    var underline: Bool = false

    var body: some View {
        text
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            // The drawn constructs are images, and an image carries no text for VoiceOver
            // to read. The linearised form is exactly the read-out `MathText.plainText`
            // exists to produce, so a statement with a fraction in it is spoken as
            // "(f(b) − f(a))/(b − a)" rather than as a gap.
            .accessibilityLabel(Text(verbatim: MathText.plainText(source)))
    }

    private func font(_ pointSize: CGFloat, isMath: Bool, isItalic: Bool) -> Font {
        if isMath || face == .serif {
            return isItalic
                ? Typeface.serifItalic(pointSize, weight) : Typeface.serif(pointSize, weight)
        }
        return isItalic
            ? Typeface.sansItalic(pointSize, weight) : Typeface.sans(pointSize, weight)
    }

    private var text: Text {
        let runs = MathText.runs(source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !runs.isEmpty else { return Text(verbatim: "") }
        let boxStyle = MathBox.Style(
            baseSize: size, weight: Self.nsWeight(weight).rawValue,
            proseIsSerif: face == .serif)
        return runs.reduce(Text(verbatim: "")) { accumulated, run in
            guard let piece = piece(for: run, boxStyle: boxStyle) else { return accumulated }
            return accumulated + piece
        }
    }

    private func piece(for run: MathText.Run, boxStyle: MathBox.Style) -> Text? {
        if run.isBox {
            // A construct that measures to nothing — an empty `\frac{}{}`, which a
            // malformed source can produce — is dropped rather than drawn as a blank
            // rectangle the width of a word.
            guard let rendered = MathBox.rendered(run, style: boxStyle) else { return nil }
            var piece = Text(Image(nsImage: rendered.image).renderingMode(.template))
                .baselineOffset(size * run.baselineMultiplier - rendered.descent)
            if underline { piece = piece.underline() }
            return piece
        }
        var piece = Text(verbatim: run.text)
            .font(
                font(
                    max(size * run.sizeMultiplier, 6), isMath: run.isMath,
                    isItalic: run.isItalic)
            )
            .baselineOffset(size * run.baselineMultiplier)
        if underline { piece = piece.underline() }
        return piece
    }

    /// SwiftUI's weights carry no raw value, and `MathBox` draws through Core Text.
    static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
