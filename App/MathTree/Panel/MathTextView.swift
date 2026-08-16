import SwiftUI

extension MathText {
    /// The pure conversion Phase 4 asks for: LaTeX-lite source in, styled attributed string
    /// out. No view state, no layout pass, no side effects — call it from anywhere.
    ///
    /// Attribute-wise this is exactly what an `NSAttributedString` build would produce: a
    /// font per run and a baseline offset per run. That equivalence is the whole point of
    /// the LaTeX-lite decision — the two-dimensional part of the notation is expressed with
    /// nothing but font size and baseline.
    static func attributedString(
        _ source: String,
        baseSize: CGFloat,
        weight: Font.Weight = .regular,
        mathDesign: Font.Design = .serif
    ) -> AttributedString {
        var output = AttributedString()
        for run in runs(source) {
            var piece = AttributedString(run.text)
            piece.font = .system(
                size: max(baseSize * run.sizeMultiplier, 6),
                weight: weight,
                design: run.isMath ? mathDesign : .default)
            piece.baselineOffset = baseSize * run.baselineMultiplier
            output.append(piece)
        }
        return output
    }
}

/// Draws LaTeX-lite source: prose in the UI face, `$…$` spans in a serif face, super- and
/// subscripts as shrunken baseline-shifted runs.
///
/// The glyphs are laid out by concatenating one `Text` per run rather than by handing
/// SwiftUI an `AttributedString`. Both carry identical information (see
/// `MathText.attributedString(_:baseSize:)`), but `Text.baselineOffset(_:)` is a documented
/// primitive whereas `Text`'s honouring of the *attribute* of the same name has varied
/// across OS releases — and this panel cannot be checked by eye from CI.
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
    }

    private func font(_ pointSize: CGFloat, isMath: Bool) -> Font {
        if isMath || face == .serif { return Typeface.serif(pointSize, weight) }
        return Typeface.sans(pointSize, weight)
    }

    private var text: Text {
        let runs = MathText.runs(source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !runs.isEmpty else { return Text(verbatim: "") }
        return runs.reduce(Text(verbatim: "")) { accumulated, run in
            var piece = Text(verbatim: run.text)
                .font(font(max(size * run.sizeMultiplier, 6), isMath: run.isMath))
                .baselineOffset(size * run.baselineMultiplier)
            if underline { piece = piece.underline() }
            return accumulated + piece
        }
    }
}
