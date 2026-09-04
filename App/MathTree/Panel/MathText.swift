import Foundation

/// The corpus's LaTeX, in two read-outs: a **linear** one for text, and a **two-dimensional**
/// one for display.
///
/// Phase 4 asked for the smallest thing that rendered the seed content acceptably and got a
/// single-pass scanner over `$…$` spans emitting styled runs — text plus a font-size
/// multiplier and a baseline shift, which is all a concatenated SwiftUI `Text` can express.
/// That is still the spine of this file, and it is still what `plainText` produces: a
/// fraction linearises to `(a)/(b)`, a radical to `√(x)`, an accent to a combining mark.
/// Accessibility labels, the corpus self-check and the answer read-back all consume that
/// form, so it is frozen.
///
/// What the *display* side no longer accepts is the linear form. `(f(b) - f(a))/(b - a)` set
/// in the same roman as the prose around it reads as prose; a reader cannot see where the
/// mathematics starts. So the scanner emits a second channel alongside the first:
///
/// - **Boxes** (`Run.box`) for the constructs a baseline shift cannot express — fractions,
///   radicals, binomials, accents and rules. They are laid out and drawn by
///   `MathBox.swift`, which owns every point of geometry; this file only says what nests in
///   what.
/// - **Italics** (`Run.isItalic`) for variables, which is the typographic convention that
///   makes `f` read as a function and not as a word. Operator names, digits, punctuation
///   and `\text{…}` stay upright, exactly as TeX sets them.
///
/// The two channels are produced in one pass and stay in step: a construct that becomes a
/// box still writes its linear form to the plain-text buffer (see `Emitter.discardingRuns`),
/// so `plainText` is byte-for-byte what it was before boxes existed.
///
/// Two deliberate properties, unchanged:
///
/// - **Pure and framework-free.** `Foundation` only, no view state, no AppKit, no SwiftUI.
///   The display adapters live in `MathBox.swift` and `MathTextView.swift`; `MathText.Check`
///   verifies this file without ever constructing a view.
/// - **Fails open.** Every unknown construct degrades to something readable and the scan
///   continues. Content will always outrun this renderer's macro table, so an unrecognised
///   macro must never swallow the rest of a statement (see `emitUnknownMacro`).
enum MathText {

    // MARK: - Output

    /// One contiguous stretch of output with uniform styling.
    ///
    /// Multipliers rather than points so the caller owns the type scale: a run is drawn at
    /// `baseSize * sizeMultiplier`, shifted `baseSize * baselineMultiplier` points up.
    struct Run: Hashable, Sendable {
        var text: String
        /// `false` for prose outside `$…$`.
        var isMath: Bool
        var sizeMultiplier: Double
        /// Positive is up (superscript), negative is down (subscript).
        var baselineMultiplier: Double
        /// Set on a variable, clear on an operator name, a digit or `\text{…}`.
        var isItalic: Bool = false
        /// Non-nil on a *box run*: a two-dimensional construct that occupies this
        /// position in the line and carries no text of its own. `text` is empty
        /// whenever this is set, and the pair is mutually exclusive by construction.
        var box: Box? = nil

        var isBox: Bool { box != nil }
    }

    /// The two-dimensional constructs, as a tree of run lists.
    ///
    /// Deliberately a small closed set rather than a general TeX box model: these are the
    /// five shapes the corpus actually writes (`\frac` ~880 uses, `\sqrt` ~1180, `\binom`
    /// ~410, accents ~740), and every one of them nests run lists that were produced by the
    /// same scanner, so a fraction inside a radical inside a superscript needs no special
    /// case anywhere.
    indirect enum Box: Hashable, Sendable {
        /// `\frac{a}{b}` — parts one style down, separated by a rule on the maths axis.
        case fraction(numerator: [Run], denominator: [Run])
        /// `\binom{n}{k}` — the same stack, parenthesised and with no rule.
        case binomial(top: [Run], bottom: [Run])
        /// `\sqrt[d]{x}` — a radical sign with a vinculum over the radicand. `degree`
        /// is empty for a square root.
        case radical(degree: [Run], radicand: [Run])
        /// `\overline{…}` / `\underline{…}` — a full-width rule above or below.
        case rule(over: Bool, content: [Run])
        /// `\hat`, `\bar`, `\vec` and friends: a mark centred over the nucleus. Drawn
        /// geometrically rather than as a combining character, which is what the
        /// Phase 4 render verification found breaks across faces.
        case accent(Accent, content: [Run], isWide: Bool)
        /// `\left( … \right)` — delimiters grown to the height of what they enclose.
        /// Either side may be empty, which is `\left.` and `\right.`.
        case delimited(open: String, content: [Run], close: String)
    }

    /// The accent marks, as shapes rather than glyphs.
    enum Accent: String, Hashable, Sendable {
        case bar, hat, tilde, vector, dot, doubleDot, check, breve, acute, grave
    }

    /// The two read-outs of one parse: styled runs for display, and a linearised
    /// plain-text form used for verification, tooltips, and accessibility.
    struct Rendering: Equatable, Sendable {
        var runs: [Run]
        var plainText: String

        var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Entry points

    static func render(_ source: String) -> Rendering {
        Renderer().render(source)
    }

    static func runs(_ source: String) -> [Run] {
        render(source).runs
    }

    /// Linearised text: super/subscripts become Unicode script characters where every
    /// character of the group has one, and `^(…)` / `_(…)` otherwise.
    static func plainText(_ source: String) -> String {
        render(source).plainText
    }

    // MARK: - Style

    /// The two-dimensional part of the renderer, expressed as font size and baseline.
    struct Style: Equatable, Sendable {
        var size: Double = 1.0
        var baseline: Double = 0.0
        var depth: Int = 0
        /// Set inside `\text{…}`, `\mathrm{…}`, `\operatorname{…}` and the other upright
        /// font selections. Suppresses the variable italic — without it `\text{if } x`
        /// reaches the reader as a slanted word, which is the tell of a renderer that
        /// italicises by position rather than by meaning.
        var isUpright: Bool = false

        /// TeX shrinks to 70 % at the first script level and 50 % at the second; the floor
        /// keeps a doubly-nested script legible at panel body size.
        private static let shrink = 0.72
        private static let minimumSize = 0.5

        func raised() -> Style {
            Style(
                size: max(size * Self.shrink, Self.minimumSize),
                baseline: baseline + 0.42 * size,
                depth: depth + 1,
                isUpright: isUpright)
        }

        func lowered() -> Style {
            Style(
                size: max(size * Self.shrink, Self.minimumSize),
                baseline: baseline - 0.20 * size,
                depth: depth + 1,
                isUpright: isUpright)
        }

        /// The style a fraction's numerator and denominator are set in. TeX sets an
        /// inline fraction one style down, which is the whole reason a quotient can sit
        /// in a line of prose without doubling the line height.
        ///
        /// The baseline resets: a box positions its own parts internally, and the box
        /// *run* carries the enclosing shift.
        func fractionPart() -> Style {
            Style(
                size: max(size * Self.shrink, Self.minimumSize),
                baseline: 0,
                depth: depth + 1,
                isUpright: isUpright)
        }

        /// The style inside a box that keeps its parts at full size — a radicand, the
        /// nucleus under an accent.
        func boxPart() -> Style {
            Style(size: size, baseline: 0, depth: depth, isUpright: isUpright)
        }
    }

    enum ScriptKind: Sendable {
        case superscript
        case `subscript`
    }

    /// How a symbol spaces itself, which is the only part of TeX's atom model worth keeping.
    enum AtomClass: Sendable {
        /// `ε`, `∞`, `Δ` — no spacing of its own. Swallows one following source space when
        /// the next thing is a word character, so `\Delta x_i` sets as `Δxᵢ` and not `Δ xᵢ`.
        case ordinary
        /// `∫`, `∑` — ordinary, except that it keeps the space in front of its operand:
        /// `\int f(x)\,dx` wants `∫ f(x) dx`, not `∫f(x) dx`.
        case largeOperator
        /// `→`, `≤`, `∈` — normalised to exactly one space on each side.
        case relation
        /// `·`, `×`, `∘` — same treatment; the corpus spaces these like relations.
        case binary
        /// `lim`, `sup`, `max` — upright, and never runs into its operand.
        case operatorName
        /// Emitted verbatim, no spacing decisions.
        case plain
    }
}

// MARK: - Emitter

extension MathText {
    /// Accumulates runs for display and, in parallel, a stack of plain-text buffers so that
    /// a script group can be folded into Unicode superscripts the moment it closes.
    fileprivate final class Emitter {
        private(set) var runs: [Run] = []
        /// One buffer per open script group; index 0 is the whole rendering.
        private var plainStack: [String] = [""]
        /// Index into `runs` where the innermost group or math span began. Trimming and
        /// decoration never reach back past it — that is what keeps a relation inside
        /// `\lim_{x \to c}` from eating the space in front of `lim`.
        private var groupRunStart: [Int] = [0]
        /// Set at a boundary so the next append starts a fresh run instead of merging into
        /// one that belongs to the enclosing group.
        private var startsNewRun = true

        var plainText: String { plainStack.first ?? "" }
        var currentPlainCount: Int { plainStack[plainStack.count - 1].count }
        var currentRunCount: Int { runs.count }
        var isCurrentGroupEmpty: Bool { runs.count == groupRunStart[groupRunStart.count - 1] }

        private var lastCharacter: Character?

        /// Whether the last thing emitted in this group was an operand — a letter,
        /// a digit, or a closing delimiter. Used to decide whether an upright
        /// operator name needs a space in front of it.
        ///
        /// `|` is deliberately absent even though it closes a group half the time:
        /// it opens one the other half, and `|\sin x|` is far commoner in this
        /// corpus than anything ending in a bar immediately followed by an
        /// operator. Including it turned `|sin x|` into `| sin x|` — caught by
        /// diffing the self-check's output across the change, which is the only
        /// reason to keep that output readable.
        var endsWithOperand: Bool {
            guard !isCurrentGroupEmpty, let last = lastCharacter else { return false }
            return last.isLetter || last.isNumber || ")]}".contains(last)
        }

        /// Whether the last thing emitted was an opening delimiter. TeX's spacing
        /// table gives Open–Rel a width of zero, which is why `(\le x)` sets as
        /// `(≤x)` and not `( ≤ x)`. Same `|` exclusion as `endsWithOperand`, and for
        /// the same reason.
        var endsWithOpenDelimiter: Bool {
            guard !isCurrentGroupEmpty, let last = lastCharacter else { return false }
            return "([{⟨⌈⌊".contains(last)
        }

        func append(_ text: String, style: Style, isMath: Bool, isItalic: Bool = false) {
            guard !text.isEmpty else { return }
            // `\text{if } x` and similar leave a doubled space; one is enough.
            if isMath, text == " ", lastCharacter == " " { return }
            lastCharacter = text.last
            if !startsNewRun, let last = runs.last, !last.isBox, last.isMath == isMath,
                last.isItalic == isItalic, last.sizeMultiplier == style.size,
                last.baselineMultiplier == style.baseline
            {
                runs[runs.count - 1].text += text
            } else {
                runs.append(
                    Run(
                        text: text, isMath: isMath, sizeMultiplier: style.size,
                        baselineMultiplier: style.baseline, isItalic: isItalic))
            }
            startsNewRun = false
            plainStack[plainStack.count - 1] += text
        }

        /// Place a two-dimensional construct in the line. Display only: the linear form
        /// was written to the plain-text buffer by `discardingRuns` just before this.
        func appendBox(_ box: Box, style: Style) {
            runs.append(
                Run(
                    text: "", isMath: true, sizeMultiplier: style.size,
                    baselineMultiplier: style.baseline, box: box))
            startsNewRun = true
        }

        /// Keep what `body` writes to the plain-text buffer and throw away the display
        /// runs it produced.
        ///
        /// This is the seam between the two read-outs. A fraction wants the linear
        /// `(a)/(b)` in `plainText` — which the scanner already knows how to produce, by
        /// running its old code path — and a box in the display runs. Running the old
        /// path inside this and appending the box afterwards gets both from one pass,
        /// and guarantees the linear form can never drift from what it was.
        ///
        /// The group-run floor is pushed so that a relation inside `body` trimming its
        /// leading space cannot reach back past the mark and delete a run the caller
        /// still owns.
        func discardingRuns(_ body: () -> Void) {
            let mark = runs.count
            groupRunStart.append(mark)
            // Force `body`'s first append to open a run of its own. Without this it
            // merges into whatever run preceded the construct, and the removal below —
            // which can only drop whole runs from `mark` on — leaves that merged text
            // behind: every fraction in the corpus arrived with a stray `(` in front of
            // it, the opening bracket of the linear form fused to the `= ` before it.
            startsNewRun = true
            body()
            if groupRunStart.count > 1 { groupRunStart.removeLast() }
            if runs.count > mark { runs.removeSubrange(mark...) }
            startsNewRun = true
        }

        /// Force the next append to open its own run.
        func breakRun() { startsNewRun = true }

        /// Drop trailing spaces so a relation can insert its own.
        func trimTrailingSpaces() {
            let floor = groupRunStart[groupRunStart.count - 1]
            while runs.count > floor {
                // A box carries no text and therefore no trailing space. Without this
                // the empty-text branch below would delete the box itself, and
                // `$\frac{1}{2} + x$` would lose its fraction to the `+`.
                if runs[runs.count - 1].isBox { break }
                var text = runs[runs.count - 1].text
                while let last = text.last, last == " " || last.isMathSpace {
                    text.removeLast()
                }
                if text.isEmpty {
                    runs.removeLast()
                    continue
                }
                runs[runs.count - 1].text = text
                break
            }
            var buffer = plainStack[plainStack.count - 1]
            while let last = buffer.last, last == " " || last.isMathSpace {
                buffer.removeLast()
            }
            plainStack[plainStack.count - 1] = buffer
            lastCharacter = buffer.last
        }

        /// A `$…$` span: a trimming floor, but no separate plain-text buffer — prose and math
        /// linearise into one string.
        func beginSpan() {
            groupRunStart.append(runs.count)
            startsNewRun = true
        }

        func endSpan() {
            if groupRunStart.count > 1 { groupRunStart.removeLast() }
            startsNewRun = true
        }

        func beginScriptGroup() {
            plainStack.append("")
            groupRunStart.append(runs.count)
            startsNewRun = true
        }

        /// Folds the group's plain text into the parent buffer as Unicode scripts when every
        /// character has a script form, and as `^(…)` / `_(…)` otherwise. The *runs* were
        /// already emitted flat with the shrunken style, so display is unaffected.
        func endScriptGroup(kind: ScriptKind) {
            let inner = plainStack.removeLast()
            if groupRunStart.count > 1 { groupRunStart.removeLast() }
            plainStack[plainStack.count - 1] += MathText.linearise(inner, kind: kind)
            startsNewRun = true
        }

        /// Interleave a combining mark after every character emitted since the given marks —
        /// how `\overline{…}` and `\underline{…}` survive both display and linearisation.
        ///
        /// Only characters sitting on `baseline` are marked. Without that, the overline of
        /// `\overline{\int_a^b}` would be drawn three times at three different heights, one
        /// under the integral sign and one under each limit.
        func decorate(
            fromRun start: Int, plainOffset: Int, with mark: Character, atBaseline baseline: Double
        ) {
            guard start < runs.count else { return }
            for index in start..<runs.count
            where runs[index].baselineMultiplier == baseline && !runs[index].isBox {
                runs[index].text = String(runs[index].text.flatMap { [$0, mark] })
            }
            let buffer = plainStack[plainStack.count - 1]
            guard buffer.count >= plainOffset else { return }
            let head = buffer.prefix(plainOffset)
            let tail = buffer.dropFirst(plainOffset)
            plainStack[plainStack.count - 1] =
                String(head)
                + String(
                    tail.flatMap { MathText.scriptCharacters.contains($0) ? [$0] : [$0, mark] })
            startsNewRun = true
        }
    }
}

extension Character {
    /// The fixed-width spaces this renderer emits, so trimming can undo them.
    fileprivate var isMathSpace: Bool {
        self == "\u{2009}" || self == "\u{2005}" || self == "\u{2003}" || self == "\u{00A0}"
    }
}

// MARK: - Renderer

extension MathText {
    fileprivate final class Renderer {
        private let emitter = Emitter()
        private var chars: [Character] = []
        private var index = 0

        /// What ends the current math span. Prose is scanned by `render(_:)` itself.
        private enum Terminator {
            case dollar
            case doubleDollar
            case parenthesis  // \)
            case bracket  // \]
            case endOfInput
        }

        func render(_ source: String) -> Rendering {
            chars = Array(source)
            index = 0
            var prose = ""

            func flushProse() {
                emitter.append(prose, style: Style(), isMath: false)
                prose = ""
            }

            while index < chars.count {
                let character = chars[index]
                if character == "\\", index + 1 < chars.count {
                    let next = chars[index + 1]
                    if next == "$" {
                        prose.append("$")
                        index += 2
                        continue
                    }
                    if next == "(" {
                        flushProse()
                        index += 2
                        scanMath(until: .parenthesis)
                        continue
                    }
                    if next == "[" {
                        flushProse()
                        index += 2
                        scanMath(until: .bracket)
                        continue
                    }
                }
                if character == "$" {
                    flushProse()
                    if index + 1 < chars.count, chars[index + 1] == "$" {
                        index += 2
                        scanMath(until: .doubleDollar)
                    } else {
                        index += 1
                        scanMath(until: .dollar)
                    }
                    continue
                }
                if character == "*", let end = emphasisEnd() {
                    flushProse()
                    emitter.append(
                        String(chars[(index + 1)..<end]), style: Style(), isMath: false,
                        isItalic: true)
                    emitter.breakRun()
                    index = end + 1
                    continue
                }
                prose.append(character)
                index += 1
            }
            flushProse()
            return Rendering(runs: emitter.runs, plainText: emitter.plainText)
        }

        /// The closing `*` of an emphasis span starting at the cursor, if there is one.
        ///
        /// The corpus writes `*this*` and means italic — sixty-odd times across the
        /// lessons and the problem bank, and the authoring guide has been telling authors
        /// to stop since the markup reached readers as literal asterisks. Rendering it is
        /// the better half of that trade: emphasis in running prose *is* italic in every
        /// book the corpus is imitating, and a rule the renderer honours cannot rot the
        /// way a rule only the linter knows about does.
        ///
        /// Conservative on purpose, and *letters and digits* specifically rather than
        /// merely non-space: the span has to open and close against a word character, so
        /// `x*(a+b)*c` keeps both asterisks as multiplication instead of italicising
        /// `(a+b)`. A `$` or a line break ends the search, so an asterisk inside
        /// mathematics never opens an emphasis at all. Every one of the corpus's 72
        /// authored spans opens and closes on a letter, so nothing is given up for it.
        private func emphasisEnd() -> Int? {
            guard let first = peek(1), first.isLetter || first.isNumber else { return nil }
            var scan = index + 2
            while scan < chars.count {
                let character = chars[scan]
                if character == "$" || character == "\n" { return nil }
                if character == "*" {
                    let previous = chars[scan - 1]
                    return previous.isLetter || previous.isNumber ? scan : nil
                }
                scan += 1
            }
            return nil
        }

        // MARK: Math scanning

        private func atTerminator(_ terminator: Terminator) -> Bool {
            atTerminator(terminator, at: index)
        }

        private func atTerminator(_ terminator: Terminator, at position: Int) -> Bool {
            guard position < chars.count else { return true }
            switch terminator {
            case .dollar:
                return chars[position] == "$"
            case .doubleDollar:
                return chars[position] == "$" && position + 1 < chars.count
                    && chars[position + 1] == "$"
            case .parenthesis:
                return chars[position] == "\\" && position + 1 < chars.count
                    && chars[position + 1] == ")"
            case .bracket:
                return chars[position] == "\\" && position + 1 < chars.count
                    && chars[position + 1] == "]"
            case .endOfInput:
                return false
            }
        }

        private func consumeTerminator(_ terminator: Terminator) {
            guard index < chars.count else { return }
            switch terminator {
            case .dollar: index += 1
            case .doubleDollar: index += 2
            case .parenthesis, .bracket: index += 2
            case .endOfInput: break
            }
        }

        /// The math loop. An unterminated span simply runs to the end of the input rather
        /// than dropping the remainder of the statement.
        private func scanMath(until terminator: Terminator, style: Style = Style()) {
            emitter.beginSpan()
            defer { emitter.endSpan() }
            while index < chars.count {
                if atTerminator(terminator) {
                    consumeTerminator(terminator)
                    return
                }
                let character = chars[index]
                switch character {
                case "\\":
                    scanMacro(style: style, terminator: terminator)
                case "^":
                    index += 1
                    scanScript(style.raised(), kind: .superscript)
                case "_":
                    index += 1
                    scanScript(style.lowered(), kind: .subscript)
                case "{", "}":
                    // Bare grouping braces carry no visual meaning once fractions and
                    // scripts have taken their own arguments.
                    index += 1
                case "'":
                    index += 1
                    emit("\u{2032}", style: style, atom: .plain, terminator: terminator)
                case "~":
                    index += 1
                    emit("\u{00A0}", style: style, atom: .plain, terminator: terminator)
                case "&":
                    index += 1
                case "-":
                    // The typographic minus, not the hyphen the keyboard produces. A
                    // hyphen in a serif face is a third of the width and sits above the
                    // maths axis, so `b - a` set with one reads as a compound word.
                    index += 1
                    emit("\u{2212}", style: style, atom: .plain, terminator: terminator)
                default:
                    index += 1
                    emit(String(character), style: style, atom: .plain, terminator: terminator)
                }
            }
        }

        /// Render a fragment in isolation and hand back only its display runs.
        ///
        /// A box's parts are drawn by `MathBox`, not spliced into the line, so they must
        /// not touch this renderer's emitter at all — neither its runs nor its plain-text
        /// buffer, which the caller is filling with the linear form at the same moment.
        /// A fresh renderer is the whole isolation mechanism.
        fileprivate func subRuns(_ fragment: [Character], style: Style) -> [Run] {
            let renderer = Renderer()
            renderer.chars = fragment
            renderer.index = 0
            renderer.scanMath(until: .endOfInput, style: style)
            return renderer.emitter.runs
        }

        /// Linearise a fragment that is already *inside* math mode — used by the
        /// single-token test, which must see `n^3` as `n³` and not as the prose `n^3`.
        func plainMathFragment(_ fragment: [Character]) -> String {
            chars = fragment
            index = 0
            scanMath(until: .endOfInput)
            return emitter.plainText
        }

        /// Render an isolated fragment (a macro argument) with a fresh cursor.
        private func scanFragment(_ fragment: [Character], style: Style) {
            let savedChars = chars
            let savedIndex = index
            chars = fragment
            index = 0
            scanMath(until: .endOfInput, style: style)
            chars = savedChars
            index = savedIndex
        }

        private func scanScript(_ style: Style, kind: ScriptKind) {
            guard let argument = takeArgument() else { return }
            emitter.beginScriptGroup()
            scanFragment(argument, style: style)
            emitter.endScriptGroup(kind: kind)
        }

        // MARK: Emission and spacing

        private func emit(
            _ text: String, style: Style, atom: AtomClass, terminator: Terminator
        ) {
            let italic = MathText.isVariable(text, atom: atom, style: style)
            switch atom {
            case .plain:
                emitter.append(text, style: style, isMath: true, isItalic: italic)

            case .largeOperator:
                // `∑`, `∫`, `∏` are set larger than the letters around them in every
                // maths face — at body size the text-height glyph reads as a stray
                // capital sigma rather than as an operator with limits hanging off it.
                // Grown about the maths axis, so the extra height is shared above and
                // below rather than pushing the whole line up.
                var large = style
                large.size = style.size * 1.32
                large.baseline = style.baseline - style.size * 0.105
                emitter.append(text, style: large, isMath: true)

            case .ordinary:
                emitter.append(text, style: style, isMath: true, isItalic: italic)
                // TeX control words swallow the space that terminates them — but only do it
                // when a word character follows, or `\varepsilon > 0` would set as `ε> 0`.
                let saved = index
                skipSpaces()
                if let next = peek(), next.isLetter || next.isNumber || next == "\\" {
                    // keep the skip
                } else {
                    index = saved
                }

            case .relation, .binary:
                // TeX's spacing table gives Open–Rel and Rel–Close/Punct a width of
                // zero: a relation next to a delimiter on the delimiter's side does
                // not space itself. Without this, `$(A, \le)$` — the standard way of
                // naming a poset, and everywhere in the Phase 9 foundations content
                // — set as `(A, ≤ )`, with a hole before the bracket. Found by
                // reading the self-check's linearised output, which is the fourth
                // corpus growth in a row to turn up a real renderer defect.
                if !emitter.isCurrentGroupEmpty, !emitter.endsWithOpenDelimiter {
                    emitter.trimTrailingSpaces()
                    if !emitter.isCurrentGroupEmpty {
                        emitter.append(" ", style: style, isMath: true)
                    }
                }
                emitter.append(text, style: style, isMath: true)
                skipSpaces()
                if index < chars.count, !atTerminator(terminator), !nextClosesAGroup() {
                    emitter.append(" ", style: style, isMath: true)
                }

            case .operatorName:
                // Symmetric with the trailing rule below, and found by the corpus
                // self-check rather than by inspection: `2x\cos(x^2)` set as
                // `2xcos(x²)`, which reads as one identifier. TeX spaces a `\mathop`
                // on both sides; the node corpus never happened to write an operator
                // directly after an operand, and the problem bank does.
                if emitter.endsWithOperand {
                    emitter.append("\u{2009}", style: style, isMath: true)
                }
                emitter.append(text, style: style, isMath: true)
                // `\sup S` must not become `supS`; an authored space already does the job.
                if let next = peek(), next.isLetter || next.isNumber {
                    emitter.append("\u{2009}", style: style, isMath: true)
                }
            }
        }

        // MARK: Cursor helpers

        private func peek(_ offset: Int = 0) -> Character? {
            let position = index + offset
            return position < chars.count ? chars[position] : nil
        }

        private func skipSpaces() {
            while index < chars.count, chars[index] == " " || chars[index] == "\n"
                || chars[index] == "\t"
            {
                index += 1
            }
        }

        /// Whether the cursor is on something that closes a group or punctuates
        /// one — the right-hand half of the Rel–Close / Rel–Punct rule above. The
        /// macro forms matter as much as the literal characters: `\rangle` and a
        /// sized `\right)` are the same atom to TeX and should read the same here.
        private func nextClosesAGroup() -> Bool {
            guard let next = peek() else { return false }
            if ")]},;".contains(next) { return true }
            guard next == "\\" else { return false }
            var offset = 1
            var name = ""
            while let character = peek(offset), character.isLetter {
                name.append(character)
                offset += 1
            }
            return Self.closingMacros.contains(name)
        }

        private static let closingMacros: Set<String> = [
            "right", "rangle", "rceil", "rfloor", "rVert", "rvert", "bigr", "Bigr", "biggr",
            "Biggr",
        ]

        /// A balanced `{…}` group, without the braces. Nil when the cursor is not on `{`.
        private func takeBraceGroup() -> [Character]? {
            let saved = index
            skipSpaces()
            guard peek() == "{" else {
                index = saved
                return nil
            }
            index += 1
            var depth = 1
            var body: [Character] = []
            while index < chars.count {
                let character = chars[index]
                if character == "\\", index + 1 < chars.count {
                    body.append(character)
                    body.append(chars[index + 1])
                    index += 2
                    continue
                }
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        return body
                    }
                }
                body.append(character)
                index += 1
            }
            return body  // unbalanced input: take what there was rather than dropping it
        }

        /// A `[…]` optional argument, e.g. the index of `\sqrt[3]{x}`.
        private func takeOptionalArgument() -> [Character]? {
            let saved = index
            skipSpaces()
            guard peek() == "[" else {
                index = saved
                return nil
            }
            index += 1
            var body: [Character] = []
            while index < chars.count, chars[index] != "]" {
                body.append(chars[index])
                index += 1
            }
            if index < chars.count { index += 1 }
            return body
        }

        /// A brace group, a single macro, or a single character — LaTeX's argument rule.
        private func takeArgument() -> [Character]? {
            if let group = takeBraceGroup() { return group }
            skipSpaces()
            guard let character = peek() else { return nil }
            if character == "\\" {
                var token: [Character] = ["\\"]
                index += 1
                if let first = peek(), !first.isLetter {
                    token.append(first)
                    index += 1
                    return token
                }
                while let next = peek(), next.isLetter {
                    token.append(next)
                    index += 1
                }
                return token
            }
            index += 1
            return [character]
        }

        // MARK: Macros

        private func scanMacro(style: Style, terminator: Terminator) {
            index += 1  // the backslash
            guard let first = peek() else { return }

            if !first.isLetter {
                index += 1
                if let literal = MathText.singleCharacterMacros[first] {
                    emit(literal, style: style, atom: .plain, terminator: terminator)
                } else {
                    // `\%`, `\&`, `\#` and friends: the escaped character is the output.
                    emit(String(first), style: style, atom: .plain, terminator: terminator)
                }
                return
            }

            var name = ""
            while let next = peek(), next.isLetter {
                name.append(next)
                index += 1
            }

            // 1. Constructs that consume arguments.
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac":
                let numerator = takeBraceGroup() ?? takeArgument() ?? []
                let denominator = takeBraceGroup() ?? takeArgument() ?? []
                emitQuotient(numerator, denominator, style: style)
                return

            case "sqrt":
                let degree = takeOptionalArgument()
                let radicand = takeArgument() ?? []
                // `fractionPart()` rather than `raised()`: the index wants the script
                // *size*, and the box decides where it sits. A raised baseline here is
                // applied twice — once by the run, once by the box — and puts the index
                // above the radical's own ascent, where it is clipped out of the image.
                let box = Box.radical(
                    degree: degree.map { subRuns($0, style: style.fractionPart()) } ?? [],
                    radicand: subRuns(radicand, style: style.boxPart()))
                emitter.discardingRuns {
                    if let degree, !degree.isEmpty {
                        emitter.beginScriptGroup()
                        scanFragment(degree, style: style.raised())
                        emitter.endScriptGroup(kind: .superscript)
                    }
                    emitter.append("\u{221A}", style: style, isMath: true)
                    emitBracketed(radicand, style: style)
                }
                emitter.appendBox(box, style: style)
                return

            case "left":
                emitPaired(style: style, terminator: terminator)
                return

            case "right", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl",
                "Biggr", "big", "Big", "bigg", "Bigg", "middle":
                // Size commands are dropped; the delimiter itself is emitted by the main
                // loop on the next turn. A `\right` reached here is one whose `\left`
                // never found it — malformed source — so it degrades to a plain bracket
                // rather than swallowing the rest of the span. `\left.` / `\right.` have
                // no delimiter to emit.
                skipSpaces()
                if peek() == "." { index += 1 }
                return

            case "mathbb":
                let argument = takeArgument() ?? []
                if argument.count == 1, let letter = argument.first,
                    let doubleStruck = MathText.doubleStruck(letter)
                {
                    emit(doubleStruck, style: style, atom: .ordinary, terminator: terminator)
                } else {
                    scanFragment(argument, style: style)
                }
                return

            case "text", "textrm", "textbf", "textsf", "texttt", "mathrm",
                "mathbf", "mathsf", "mathtt", "mathcal", "mathfrak", "mathscr", "boldsymbol",
                "bm", "operatorname", "mbox", "hbox":
                // No *face* variation beyond upright/italic, but the upright half is not
                // cosmetic: `\text{if }`, `\operatorname{sd}` and `\mathrm{d}x` are words
                // and operator names, and setting them in the variable italic is the
                // single commonest way a maths renderer looks wrong.
                let argument = takeArgument() ?? []
                var upright = style
                upright.isUpright = true
                scanFragment(argument, style: upright)
                return

            case "textit", "mathit", "emph":
                let argument = takeArgument() ?? []
                var italic = style
                italic.isUpright = false
                scanFragment(argument, style: italic)
                return

            case "underline", "overline", "widehat", "widetilde", "overrightarrow", "hat",
                "bar", "vec", "tilde", "dot", "ddot", "check", "breve", "acute", "grave":
                let argument = takeArgument() ?? []
                let content = subRuns(argument, style: style.boxPart())
                let box = MathText.decoration(named: name, over: content)
                // Plain text keeps the combining mark it has always used: `X̄` is what an
                // accessibility label and the self-check's read-out want, and neither can
                // show a drawn rule.
                emitter.discardingRuns {
                    emitter.breakRun()
                    let runStart = emitter.currentRunCount
                    let plainStart = emitter.currentPlainCount
                    scanFragment(argument, style: style)
                    if let mark = MathText.combiningMarks[name] {
                        emitter.decorate(
                            fromRun: runStart, plainOffset: plainStart, with: mark,
                            atBaseline: style.baseline)
                    }
                }
                emitter.appendBox(box, style: style)
                return

            case "binom", "dbinom", "tbinom":
                let top = takeBraceGroup() ?? takeArgument() ?? []
                let bottom = takeBraceGroup() ?? takeArgument() ?? []
                let box = Box.binomial(
                    top: subRuns(top, style: style.fractionPart()),
                    bottom: subRuns(bottom, style: style.fractionPart()))
                emitter.discardingRuns {
                    emitter.append("C(", style: style, isMath: true)
                    scanFragment(top, style: style)
                    emitter.append(", ", style: style, isMath: true)
                    scanFragment(bottom, style: style)
                    emitter.append(")", style: style, isMath: true)
                }
                emitter.appendBox(box, style: style)
                return

            case "pmod":
                let argument = takeArgument() ?? []
                // `\pmod` carries its own leading space, so the authored one in
                // `b \pmod{n}` has to go or the two add up — `a ≡ b  (mod n)`.
                // `append`'s doubled-space guard cannot see this one: it fires on a
                // lone `" "`, and this is a six-character string that starts with one.
                emitter.trimTrailingSpaces()
                emitter.append(" (mod ", style: style, isMath: true)
                scanFragment(argument, style: style)
                emitter.append(")", style: style, isMath: true)
                return

            case "limits", "nolimits", "displaystyle", "textstyle", "scriptstyle",
                "scriptscriptstyle", "notag", "nonumber":
                // Typesetting hints with no linear equivalent.
                return

            case "phantom", "hphantom", "vphantom":
                _ = takeArgument()
                return

            case "substack":
                let argument = takeArgument() ?? []
                scanFragment(argument, style: style)
                return

            default:
                break
            }

            // 2. Table lookups.
            if let (text, atom) = MathText.symbols[name] {
                emit(text, style: style, atom: atom, terminator: terminator)
                return
            }
            if MathText.operatorNames.contains(name) {
                emit(name, style: style, atom: .operatorName, terminator: terminator)
                return
            }
            if let space = MathText.spacingMacros[name] {
                emitter.append(space, style: style, isMath: true)
                return
            }

            // 3. Unknown. Fail open (see the type doc).
            emitUnknownMacro(named: name, style: style, terminator: terminator)
        }

        /// An unrecognised macro renders its braced argument if it has one, and otherwise its
        /// own name as upright text. Never a dropped remainder, never a stray backslash —
        /// future content will contain macros this table has never heard of, and a statement
        /// that renders slightly wrong beats a statement that renders half.
        private func emitUnknownMacro(named name: String, style: Style, terminator: Terminator) {
            if let argument = takeBraceGroup() {
                scanFragment(argument, style: style)
                // A macro with two braced arguments (some unknown binary construct) still
                // renders both rather than leaving the second orphaned in the output.
                while let extra = takeBraceGroup() {
                    emitter.append(" ", style: style, isMath: true)
                    scanFragment(extra, style: style)
                }
                return
            }
            emit(name, style: style, atom: .operatorName, terminator: terminator)
        }

        // MARK: Fractions

        // MARK: Paired delimiters

        /// `\left( … \right)`: the enclosed span becomes one box, so the brackets can be
        /// grown to the height of what they hold.
        ///
        /// Worth the machinery because the corpus pairs them with exactly the constructs
        /// that are now tall — `\left(\frac{a}{b}\right)^2` is the commonest shape in the
        /// whole quant tree, and a text-size parenthesis beside a full-height fraction is
        /// the single most obvious tell that a renderer is faking it.
        ///
        /// The cursor is just past `\left`. Nesting is counted, so the inner pair of
        /// `\left(\left[x\right]\right)` closes first, and a `\left` whose `\right` never
        /// arrives — or arrives after the span ends — degrades to a plain bracket.
        private func emitPaired(style: Style, terminator: Terminator) {
            let open = takeDelimiter() ?? ""
            guard let (content, close) = takeUntilMatchingRight(terminator: terminator) else {
                if !open.isEmpty { emitter.append(open, style: style, isMath: true) }
                return
            }
            let box = Box.delimited(
                open: open, content: subRuns(content, style: style.boxPart()), close: close)
            emitter.discardingRuns {
                if !open.isEmpty { emitter.append(open, style: style, isMath: true) }
                scanFragment(content, style: style)
                if !close.isEmpty { emitter.append(close, style: style, isMath: true) }
            }
            emitter.appendBox(box, style: style)
        }

        /// The delimiter token after `\left` or `\right`: a literal bracket, an escaped
        /// one, or a macro. `.` is TeX's empty delimiter and comes back as `""`.
        private func takeDelimiter() -> String? {
            skipSpaces()
            guard let character = peek() else { return nil }
            if character == "." {
                index += 1
                return ""
            }
            guard character == "\\" else {
                index += 1
                return String(character)
            }
            index += 1
            guard let first = peek() else { return nil }
            if !first.isLetter {
                index += 1
                return MathText.singleCharacterMacros[first] ?? String(first)
            }
            var name = ""
            while let next = peek(), next.isLetter {
                name.append(next)
                index += 1
            }
            return MathText.symbols[name]?.0 ?? ""
        }

        /// Everything up to the `\right` that matches the `\left` just read, plus that
        /// `\right`'s delimiter. Nil when the span ends first, which leaves the cursor
        /// untouched so the caller can fall back.
        private func takeUntilMatchingRight(terminator: Terminator) -> ([Character], String)? {
            var depth = 0
            var scan = index
            var content: [Character] = []
            while scan < chars.count, !atTerminator(terminator, at: scan) {
                guard chars[scan] == "\\", scan + 1 < chars.count else {
                    content.append(chars[scan])
                    scan += 1
                    continue
                }
                let name = macroName(at: scan + 1)
                guard !name.isEmpty else {
                    // An escaped character — `\{`, `\|` — copied whole, or the brace
                    // would reach the sub-render as a grouping brace.
                    content.append(chars[scan])
                    content.append(chars[scan + 1])
                    scan += 2
                    continue
                }
                if name == "right", depth == 0 {
                    index = scan + 1 + name.count
                    return (content, takeDelimiter() ?? "")
                }
                if name == "left" { depth += 1 }
                if name == "right" { depth -= 1 }
                content.append(contentsOf: chars[scan..<(scan + 1 + name.count)])
                scan += 1 + name.count
            }
            return nil
        }

        private func macroName(at position: Int) -> String {
            var name = ""
            var scan = position
            while scan < chars.count, chars[scan].isLetter {
                name.append(chars[scan])
                scan += 1
            }
            return name
        }

        /// A fraction, in both read-outs at once.
        ///
        /// Display gets a real quotient: numerator over denominator, one style down, with a
        /// rule between them on the maths axis. Plain text gets what it always got —
        /// `(a)/(b)`, dropping the parentheses around a single token so the corpus's
        /// `\dfrac{f(b) - f(a)}{b - a}` reads `(f(b) − f(a))/(b − a)` while `\dfrac{1}{3}`
        /// reads `1/3`.
        private func emitQuotient(
            _ numerator: [Character], _ denominator: [Character], style: Style
        ) {
            let part = style.fractionPart()
            let box = Box.fraction(
                numerator: subRuns(numerator, style: part),
                denominator: subRuns(denominator, style: part))
            emitter.discardingRuns {
                emitBracketed(numerator, style: style)
                emitter.append("/", style: style, isMath: true)
                emitBracketed(denominator, style: style)
            }
            emitter.appendBox(box, style: style)
        }

        private func emitBracketed(_ argument: [Character], style: Style) {
            let needsParentheses = MathText.needsParentheses(argument)
            if needsParentheses { emitter.append("(", style: style, isMath: true) }
            scanFragment(argument, style: style)
            if needsParentheses { emitter.append(")", style: style, isMath: true) }
        }
    }
}

// MARK: - Italic

extension MathText {
    /// Whether a stretch of maths sets in the italic face.
    ///
    /// TeX's rule, kept to the part that matters: **a variable is italic and nothing else
    /// is**. That single distinction is what separates mathematics from the prose around
    /// it on the page — without it `f` in "if $f$ is continuous" is the same three strokes
    /// as the `f` in "of", and a statement set in a serif reads as a sentence with odd
    /// spacing rather than as notation.
    ///
    /// The atom class does the work. A letter the scanner read straight from the source is
    /// a variable; a letter that arrived as part of `\sin` or `\max` is an operator name
    /// and stays upright, which is exactly the distinction TeX's `\mathop` draws.
    static func isVariable(_ text: String, atom: AtomClass, style: Style) -> Bool {
        guard !style.isUpright, !text.isEmpty else { return false }
        switch atom {
        case .operatorName, .relation, .binary, .largeOperator:
            return false
        case .plain:
            return text.allSatisfy { $0.isLetter }
        case .ordinary:
            // Symbol-table entries: lower-case Greek is a variable and sets like one.
            // Upper-case Greek, `∞`, `∅`, `ℝ` and the rest are upright in every maths
            // face — a slanted `∞` is not a thing anyone has ever wanted.
            return text.unicodeScalars.allSatisfy(isLowerCaseGreek)
        }
    }

    private static func isLowerCaseGreek(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3B1...0x3C9:  // α … ω
            return true
        case 0x3D1, 0x3D5, 0x3D6, 0x3F0, 0x3F1, 0x3F5:  // ϑ ϕ ϖ ϰ ϱ ϵ
            return true
        default:
            return false
        }
    }
}

// MARK: - Single-token test

extension MathText {
    /// True when the argument is more than one atom and therefore needs bracketing in the
    /// linear fraction form. Script characters do not count towards the atom count, so
    /// `n^3` is one atom (`1/n³`) but `2n` is two (`1/(2n)`).
    fileprivate static func needsParentheses(_ argument: [Character]) -> Bool {
        let rendered = Renderer().plainMathFragment(argument)
        let base = rendered.filter { !scriptCharacters.contains($0) }
        guard base.count == 1, let only = base.first else { return true }
        return "+-\u{2212}*/=<>()[]{}|,;: \u{2009}\u{2005}".contains(only)
    }
}

// MARK: - Plain-text linearisation

extension MathText {
    fileprivate static func linearise(_ group: String, kind: ScriptKind) -> String {
        let table = kind == .superscript ? superscriptCharacters : subscriptCharacters
        var mapped = ""
        var complete = !group.isEmpty
        for character in group {
            if let replacement = table[character] {
                mapped.append(replacement)
            } else {
                complete = false
                break
            }
        }
        if complete { return mapped }
        let marker = kind == .superscript ? "^" : "_"
        if group.count == 1 { return marker + group }
        return marker + "(" + group + ")"
    }

    fileprivate static let superscriptCharacters: [Character: Character] = {
        var table: [Character: Character] = [:]
        let pairs: [(String, String)] = [
            ("0123456789", "⁰¹²³⁴⁵⁶⁷⁸⁹"),
            // Parentheses are deliberately absent: a group like `g(b)` should fall back to
            // `^(g(b))` so that it matches the `_(g(a))` beside it, rather than half of
            // `\int_{g(a)}^{g(b)}` linearising one way and half the other.
            ("+-=", "⁺⁻⁼"),
            ("abcdefghijklmnoprstuvwxyz", "ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ"),
            ("ABDEGHIJKLMNOPRTUVW", "ᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂ"),
        ]
        for (from, to) in pairs {
            for (source, target) in zip(from, to) { table[source] = target }
        }
        table["\u{2212}"] = "⁻"
        return table
    }()

    fileprivate static let subscriptCharacters: [Character: Character] = {
        var table: [Character: Character] = [:]
        let pairs: [(String, String)] = [
            ("0123456789", "₀₁₂₃₄₅₆₇₈₉"),
            ("+-=", "₊₋₌"),
            ("aehijklmnoprstuvx", "ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ"),
            ("βγρφχ", "ᵦᵧᵨᵩᵪ"),
        ]
        for (from, to) in pairs {
            for (source, target) in zip(from, to) { table[source] = target }
        }
        table["\u{2212}"] = "₋"
        return table
    }()

    fileprivate static let scriptCharacters: Set<Character> = {
        var set = Set(superscriptCharacters.values)
        set.formUnion(subscriptCharacters.values)
        return set
    }()
}

// MARK: - Tables

extension MathText {

    /// Blackboard bold. The seven letters Unicode assigned before the Mathematical
    /// Alphanumeric Symbols block exists as holes in that block.
    fileprivate static func doubleStruck(_ letter: Character) -> String? {
        switch letter {
        case "C": return "\u{2102}"
        case "H": return "\u{210D}"
        case "N": return "\u{2115}"
        case "P": return "\u{2119}"
        case "Q": return "\u{211A}"
        case "R": return "\u{211D}"
        case "Z": return "\u{2124}"
        default: break
        }
        guard let ascii = letter.asciiValue else { return nil }
        if ascii >= UInt8(ascii: "A"), ascii <= UInt8(ascii: "Z") {
            let base: UInt32 = 0x1D538
            return String(
                UnicodeScalar(base + UInt32(ascii - UInt8(ascii: "A")))!)
        }
        if ascii >= UInt8(ascii: "a"), ascii <= UInt8(ascii: "z") {
            let base: UInt32 = 0x1D552
            return String(
                UnicodeScalar(base + UInt32(ascii - UInt8(ascii: "a")))!)
        }
        return nil
    }

    /// The box a decoration macro draws.
    ///
    /// The split TeX draws and the corpus relies on: `\bar{X}` is a short mark centred over
    /// one letter, `\overline{X + Y}` is a rule the full width of what it covers. Rendering
    /// both as the same combining character — which is what this did before — puts one
    /// macron over the `X` of `\overline{XY}` and none over the `Y`.
    fileprivate static func decoration(named name: String, over content: [Run]) -> Box {
        switch name {
        case "overline": return .rule(over: true, content: content)
        case "underline": return .rule(over: false, content: content)
        case "widehat": return .accent(.hat, content: content, isWide: true)
        case "widetilde": return .accent(.tilde, content: content, isWide: true)
        case "overrightarrow": return .accent(.vector, content: content, isWide: true)
        case "vec": return .accent(.vector, content: content, isWide: false)
        case "hat": return .accent(.hat, content: content, isWide: false)
        case "bar": return .accent(.bar, content: content, isWide: false)
        case "tilde": return .accent(.tilde, content: content, isWide: false)
        case "dot": return .accent(.dot, content: content, isWide: false)
        case "ddot": return .accent(.doubleDot, content: content, isWide: false)
        case "check": return .accent(.check, content: content, isWide: false)
        case "breve": return .accent(.breve, content: content, isWide: false)
        case "acute": return .accent(.acute, content: content, isWide: false)
        default: return .accent(.grave, content: content, isWide: false)
        }
    }

    fileprivate static let combiningMarks: [String: Character] = [
        "underline": "\u{0332}",
        "overline": "\u{0305}",
        "bar": "\u{0304}",
        "hat": "\u{0302}",
        "widehat": "\u{0302}",
        "tilde": "\u{0303}",
        "widetilde": "\u{0303}",
        "vec": "\u{20D7}",
        "overrightarrow": "\u{20D7}",
        "dot": "\u{0307}",
        "ddot": "\u{0308}",
        "check": "\u{030C}",
        "breve": "\u{0306}",
        "acute": "\u{0301}",
        "grave": "\u{0300}",
    ]

    /// `\,` and friends. `\!` is a negative space and simply disappears.
    fileprivate static let singleCharacterMacros: [Character: String] = [
        ",": "\u{2009}",  // thin
        ":": "\u{2005}",  // medium
        ";": "\u{2005}",
        " ": " ",
        "!": "",
        "{": "{",
        "}": "}",
        "|": "\u{2016}",
        "\\": "\n",
        "$": "$",
        "%": "%",
        "&": "&",
        "#": "#",
        "_": "_",
    ]

    fileprivate static let spacingMacros: [String: String] = [
        "quad": "\u{2003}",
        "qquad": "\u{2003}\u{2003}",
        "thinspace": "\u{2009}",
        "medspace": "\u{2005}",
        "thickspace": "\u{2004}",
        "negthinspace": "",
        "negmedspace": "",
        "space": " ",
        "enspace": "\u{2002}",
        "hspace": "\u{2003}",
    ]

    /// Upright multi-letter operators. Emitted as their own name, with a thin space before a
    /// following operand.
    fileprivate static let operatorNames: Set<String> = [
        "lim", "limsup", "liminf", "sup", "inf", "max", "min", "arg", "det", "dim", "ker",
        "deg", "gcd", "lcm", "exp", "log", "ln", "lg", "sin", "cos", "tan", "cot", "sec",
        "csc", "sinh", "cosh", "tanh", "coth", "arcsin", "arccos", "arctan", "Pr", "hom",
        "mod", "bmod", "sgn", "tr", "rank", "span", "supp", "id", "Aut", "Hom", "End", "im",
        // Phase 9's branches, added ahead of the content that needs them: an author
        // who reaches for `\Gal` and finds nothing writes around it, and the
        // work-around is what ends up in the corpus permanently.
        "Gal", "Sym", "Alt", "Inn", "ord", "char", "Var", "Cov", "Cor", "Res", "curl",
        "grad", "diam", "cl", "Fix", "Stab", "Orb", "proj", "nullity", "Ext", "Tor",
        "cis", "erf", "sech", "csch", "arcsec", "arccsc", "arccot", "adj", "cof", "supp",
    ]

    /// The symbol table. Everything the corpus uses, plus the neighbourhood of macros that
    /// undergraduate content will reach for next.
    fileprivate static let symbols: [String: (String, AtomClass)] = [
        // Greek, lower case
        "alpha": ("α", .ordinary), "beta": ("β", .ordinary), "gamma": ("γ", .ordinary),
        "delta": ("δ", .ordinary), "epsilon": ("ϵ", .ordinary), "varepsilon": ("ε", .ordinary),
        "zeta": ("ζ", .ordinary), "eta": ("η", .ordinary), "theta": ("θ", .ordinary),
        "vartheta": ("ϑ", .ordinary), "iota": ("ι", .ordinary), "kappa": ("κ", .ordinary),
        "lambda": ("λ", .ordinary), "mu": ("μ", .ordinary), "nu": ("ν", .ordinary),
        "xi": ("ξ", .ordinary), "omicron": ("ο", .ordinary), "pi": ("π", .ordinary),
        "varpi": ("ϖ", .ordinary), "rho": ("ρ", .ordinary), "varrho": ("ϱ", .ordinary),
        "sigma": ("σ", .ordinary), "varsigma": ("ς", .ordinary), "tau": ("τ", .ordinary),
        "upsilon": ("υ", .ordinary), "phi": ("ϕ", .ordinary), "varphi": ("φ", .ordinary),
        "chi": ("χ", .ordinary), "psi": ("ψ", .ordinary), "omega": ("ω", .ordinary),

        // Greek, upper case
        "Gamma": ("Γ", .ordinary), "Delta": ("Δ", .ordinary), "Theta": ("Θ", .ordinary),
        "Lambda": ("Λ", .ordinary), "Xi": ("Ξ", .ordinary), "Pi": ("Π", .ordinary),
        "Sigma": ("Σ", .ordinary), "Upsilon": ("Υ", .ordinary), "Phi": ("Φ", .ordinary),
        "Psi": ("Ψ", .ordinary), "Omega": ("Ω", .ordinary),

        // Relations
        "le": ("≤", .relation), "leq": ("≤", .relation), "ge": ("≥", .relation),
        "geq": ("≥", .relation), "ne": ("≠", .relation), "neq": ("≠", .relation),
        "equiv": ("≡", .relation), "approx": ("≈", .relation), "sim": ("∼", .relation),
        "simeq": ("≃", .relation), "cong": ("≅", .relation), "propto": ("∝", .relation),
        "in": ("∈", .relation), "notin": ("∉", .relation), "ni": ("∋", .relation),
        "subset": ("⊂", .relation), "subseteq": ("⊆", .relation), "supset": ("⊃", .relation),
        "supseteq": ("⊇", .relation), "subsetneq": ("⊊", .relation),
        "supsetneq": ("⊋", .relation), "ll": ("≪", .relation), "gg": ("≫", .relation),
        "perp": ("⊥", .relation), "parallel": ("∥", .relation), "mid": ("∣", .relation),
        "models": ("⊨", .relation), "vdash": ("⊢", .relation), "doteq": ("≐", .relation),
        "asymp": ("≍", .relation), "leqslant": ("⩽", .relation), "geqslant": ("⩾", .relation),
        // Phase 9. `\nmid` is the one that would otherwise be written around every
        // time number theory says "does not divide".
        "nmid": ("∤", .relation), "prec": ("≺", .relation), "succ": ("≻", .relation),
        "preceq": ("⪯", .relation), "succeq": ("⪰", .relation),
        "triangleq": ("≜", .relation), "coloneqq": ("≔", .relation),
        "lhd": ("⊲", .relation), "rhd": ("⊳", .relation),
        "unlhd": ("⊴", .relation), "unrhd": ("⊵", .relation),
        "nsubseteq": ("⊈", .relation), "ncong": ("≇", .relation),
        "upharpoonright": ("↾", .relation), "restriction": ("↾", .relation),

        // Arrows (relations, for spacing purposes)
        "to": ("→", .relation), "rightarrow": ("→", .relation),
        "longrightarrow": ("⟶", .relation), "Rightarrow": ("⇒", .relation),
        "implies": ("⇒", .relation), "leftarrow": ("←", .relation),
        "Leftarrow": ("⇐", .relation), "impliedby": ("⇐", .relation),
        "leftrightarrow": ("↔", .relation), "Leftrightarrow": ("⇔", .relation),
        "iff": ("⇔", .relation), "mapsto": ("↦", .relation), "longmapsto": ("⟼", .relation),
        "hookrightarrow": ("↪", .relation), "twoheadrightarrow": ("↠", .relation),
        "uparrow": ("↑", .ordinary), "downarrow": ("↓", .ordinary),
        "nearrow": ("↗", .ordinary), "searrow": ("↘", .ordinary),

        // Binary operators
        "pm": ("±", .binary), "mp": ("∓", .binary), "times": ("×", .binary),
        "div": ("÷", .binary), "cdot": ("·", .binary), "ast": ("∗", .binary),
        "star": ("⋆", .binary), "circ": ("∘", .binary), "bullet": ("∙", .binary),
        "oplus": ("⊕", .binary), "ominus": ("⊖", .binary), "otimes": ("⊗", .binary),
        "oslash": ("⊘", .binary), "odot": ("⊙", .binary), "cup": ("∪", .binary),
        "cap": ("∩", .binary), "sqcup": ("⊔", .binary), "sqcap": ("⊓", .binary),
        "vee": ("∨", .binary), "wedge": ("∧", .binary), "lor": ("∨", .binary),
        "land": ("∧", .binary), "setminus": ("∖", .binary), "amalg": ("⨿", .binary),
        "triangleleft": ("◁", .binary), "triangleright": ("▷", .binary),
        "rtimes": ("⋊", .binary), "ltimes": ("⋉", .binary),
        "complement": ("∁", .ordinary), "square": ("□", .ordinary),
        "blacksquare": ("■", .ordinary),

        // Large operators
        "sum": ("∑", .largeOperator), "prod": ("∏", .largeOperator),
        "coprod": ("∐", .largeOperator), "int": ("∫", .largeOperator),
        "iint": ("∬", .largeOperator), "iiint": ("∭", .largeOperator),
        "oint": ("∮", .largeOperator), "bigcup": ("⋃", .largeOperator),
        "bigcap": ("⋂", .largeOperator), "bigsqcup": ("⨆", .largeOperator),
        "bigodot": ("⨀", .largeOperator), "bigoplus": ("⨁", .largeOperator),
        "bigotimes": ("⨂", .largeOperator), "bigvee": ("⋁", .largeOperator),
        "bigwedge": ("⋀", .largeOperator),

        // Miscellaneous symbols
        "infty": ("∞", .ordinary), "partial": ("∂", .ordinary), "nabla": ("∇", .ordinary),
        "forall": ("∀", .ordinary), "exists": ("∃", .ordinary), "nexists": ("∄", .ordinary),
        "neg": ("¬", .ordinary), "lnot": ("¬", .ordinary), "emptyset": ("∅", .ordinary),
        "varnothing": ("∅", .ordinary), "aleph": ("ℵ", .ordinary), "hbar": ("ℏ", .ordinary),
        "ell": ("ℓ", .ordinary), "Re": ("ℜ", .ordinary), "Im": ("ℑ", .ordinary),
        "wp": ("℘", .ordinary), "prime": ("′", .ordinary), "angle": ("∠", .ordinary),
        "therefore": ("∴", .ordinary), "because": ("∵", .ordinary), "surd": ("√", .ordinary),
        "top": ("⊤", .ordinary), "bot": ("⊥", .ordinary), "dagger": ("†", .ordinary),
        "degree": ("°", .ordinary), "backslash": ("\\", .ordinary),

        // Ellipses
        "dots": ("…", .ordinary), "ldots": ("…", .ordinary), "cdots": ("⋯", .ordinary),
        "vdots": ("⋮", .ordinary), "ddots": ("⋱", .ordinary), "dotsc": ("…", .ordinary),
        "dotsb": ("⋯", .ordinary), "dotsm": ("⋯", .ordinary),

        // Delimiters
        "langle": ("⟨", .ordinary), "rangle": ("⟩", .ordinary), "lceil": ("⌈", .ordinary),
        "rceil": ("⌉", .ordinary), "lfloor": ("⌊", .ordinary), "rfloor": ("⌋", .ordinary),
        "lvert": ("|", .ordinary), "rvert": ("|", .ordinary), "lVert": ("‖", .ordinary),
        "rVert": ("‖", .ordinary), "vert": ("|", .ordinary), "Vert": ("‖", .ordinary),
    ]
}
