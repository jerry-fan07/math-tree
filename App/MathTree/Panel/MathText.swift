import Foundation

/// LaTeX-lite: the smallest thing that renders the content corpus acceptably.
///
/// Phase 4 of implementation-plan.md asks for an evaluation of "`NSAttributedString`-based
/// LaTeX-lite vs. bundling a math-layout approach" and says the smallest thing that renders
/// the seed content wins. This is that thing: a single-pass scanner over `$…$` spans that
/// emits **styled runs** — text plus a font-size multiplier and a baseline shift — which is
/// exactly the expressive power an `NSAttributedString` (or a concatenated SwiftUI `Text`)
/// has. There is no box model, no fraction bar, no radical rule. Fractions linearise to
/// `(a)/(b)`; super/subscripts are the only two-dimensional construct, and they are done
/// with baseline offsets.
///
/// Two deliberate properties:
///
/// - **Pure and framework-free.** `Foundation` only, no view state, no AppKit, no SwiftUI.
///   The display adapter lives in `MathTextView.swift`; `MathText.Check` verifies this file
///   without ever constructing a view.
/// - **Fails open.** Every unknown construct degrades to something readable and the scan
///   continues. Content will always outrun this renderer's macro table, so an unrecognised
///   macro must never swallow the rest of a statement (see `emitUnknownMacro`).
enum MathText {

    // MARK: - Output

    /// One contiguous stretch of output with uniform styling.
    ///
    /// Multipliers rather than points so the caller owns the type scale: a run is drawn at
    /// `baseSize * sizeMultiplier`, shifted `baseSize * baselineMultiplier` points up.
    struct Run: Equatable, Sendable {
        var text: String
        /// `false` for prose outside `$…$`.
        var isMath: Bool
        var sizeMultiplier: Double
        /// Positive is up (superscript), negative is down (subscript).
        var baselineMultiplier: Double
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

        /// TeX shrinks to 70 % at the first script level and 50 % at the second; the floor
        /// keeps a doubly-nested script legible at panel body size.
        private static let shrink = 0.72
        private static let minimumSize = 0.5

        func raised() -> Style {
            Style(
                size: max(size * Self.shrink, Self.minimumSize),
                baseline: baseline + 0.42 * size,
                depth: depth + 1)
        }

        func lowered() -> Style {
            Style(
                size: max(size * Self.shrink, Self.minimumSize),
                baseline: baseline - 0.20 * size,
                depth: depth + 1)
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

        func append(_ text: String, style: Style, isMath: Bool) {
            guard !text.isEmpty else { return }
            // `\text{if } x` and similar leave a doubled space; one is enough.
            if isMath, text == " ", lastCharacter == " " { return }
            lastCharacter = text.last
            if !startsNewRun, let last = runs.last, last.isMath == isMath,
                last.sizeMultiplier == style.size, last.baselineMultiplier == style.baseline
            {
                runs[runs.count - 1].text += text
            } else {
                runs.append(
                    Run(
                        text: text, isMath: isMath, sizeMultiplier: style.size,
                        baselineMultiplier: style.baseline))
            }
            startsNewRun = false
            plainStack[plainStack.count - 1] += text
        }

        /// Force the next append to open its own run.
        func breakRun() { startsNewRun = true }

        /// Drop trailing spaces so a relation can insert its own.
        func trimTrailingSpaces() {
            let floor = groupRunStart[groupRunStart.count - 1]
            while runs.count > floor {
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
            for index in start..<runs.count where runs[index].baselineMultiplier == baseline {
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
                prose.append(character)
                index += 1
            }
            flushProse()
            return Rendering(runs: emitter.runs, plainText: emitter.plainText)
        }

        // MARK: Math scanning

        private func atTerminator(_ terminator: Terminator) -> Bool {
            guard index < chars.count else { return true }
            switch terminator {
            case .dollar:
                return chars[index] == "$"
            case .doubleDollar:
                return chars[index] == "$" && index + 1 < chars.count && chars[index + 1] == "$"
            case .parenthesis:
                return chars[index] == "\\" && index + 1 < chars.count && chars[index + 1] == ")"
            case .bracket:
                return chars[index] == "\\" && index + 1 < chars.count && chars[index + 1] == "]"
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
                default:
                    index += 1
                    emit(String(character), style: style, atom: .plain, terminator: terminator)
                }
            }
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
            switch atom {
            case .plain:
                emitter.append(text, style: style, isMath: true)

            case .largeOperator:
                emitter.append(text, style: style, isMath: true)

            case .ordinary:
                emitter.append(text, style: style, isMath: true)
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
                if !emitter.isCurrentGroupEmpty {
                    emitter.trimTrailingSpaces()
                    if !emitter.isCurrentGroupEmpty {
                        emitter.append(" ", style: style, isMath: true)
                    }
                }
                emitter.append(text, style: style, isMath: true)
                skipSpaces()
                if index < chars.count, !atTerminator(terminator) {
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
                if let degree, !degree.isEmpty {
                    emitter.beginScriptGroup()
                    scanFragment(degree, style: style.raised())
                    emitter.endScriptGroup(kind: .superscript)
                }
                emitter.append("\u{221A}", style: style, isMath: true)
                let radicand = takeArgument() ?? []
                emitBracketed(radicand, style: style)
                return

            case "left", "right", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl",
                "Biggr", "big", "Big", "bigg", "Bigg", "middle":
                // Size commands are dropped; the delimiter itself is emitted by the main
                // loop on the next turn. `\left.` / `\right.` have no delimiter to emit.
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

            case "text", "textrm", "textit", "textbf", "textsf", "texttt", "mathrm", "mathit",
                "mathbf", "mathsf", "mathtt", "mathcal", "mathfrak", "mathscr", "boldsymbol",
                "bm", "operatorname", "mbox", "hbox", "emph":
                // No font variation in this renderer: the argument is the content.
                let argument = takeArgument() ?? []
                scanFragment(argument, style: style)
                return

            case "underline", "overline", "widehat", "widetilde", "overrightarrow", "hat",
                "bar", "vec", "tilde", "dot", "ddot", "check", "breve", "acute", "grave":
                let argument = takeArgument() ?? []
                emitter.breakRun()
                let runStart = emitter.currentRunCount
                let plainStart = emitter.currentPlainCount
                scanFragment(argument, style: style)
                if let mark = MathText.combiningMarks[name] {
                    emitter.decorate(
                        fromRun: runStart, plainOffset: plainStart, with: mark,
                        atBaseline: style.baseline)
                }
                return

            case "binom", "dbinom", "tbinom":
                let top = takeBraceGroup() ?? takeArgument() ?? []
                let bottom = takeBraceGroup() ?? takeArgument() ?? []
                emitter.append("C(", style: style, isMath: true)
                scanFragment(top, style: style)
                emitter.append(", ", style: style, isMath: true)
                scanFragment(bottom, style: style)
                emitter.append(")", style: style, isMath: true)
                return

            case "pmod":
                let argument = takeArgument() ?? []
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

        /// `\frac{a}{b}` → `(a)/(b)`, dropping the parentheses around a single token so the
        /// corpus's `\dfrac{f(b) - f(a)}{b - a}` reads `(f(b) - f(a))/(b - a)` while
        /// `\dfrac{1}{3}` reads `1/3`.
        private func emitQuotient(
            _ numerator: [Character], _ denominator: [Character], style: Style
        ) {
            emitBracketed(numerator, style: style)
            emitter.append("/", style: style, isMath: true)
            emitBracketed(denominator, style: style)
        }

        private func emitBracketed(_ argument: [Character], style: Style) {
            let needsParentheses = MathText.needsParentheses(argument)
            if needsParentheses { emitter.append("(", style: style, isMath: true) }
            scanFragment(argument, style: style)
            if needsParentheses { emitter.append(")", style: style, isMath: true) }
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
        return "+-*/=<>()[]{}|,;: \u{2009}\u{2005}".contains(only)
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

        // Large operators
        "sum": ("∑", .largeOperator), "prod": ("∏", .largeOperator),
        "coprod": ("∐", .largeOperator), "int": ("∫", .largeOperator),
        "iint": ("∬", .largeOperator), "iiint": ("∭", .largeOperator),
        "oint": ("∮", .largeOperator), "bigcup": ("⋃", .largeOperator),
        "bigcap": ("⋂", .largeOperator), "bigoplus": ("⨁", .largeOperator),
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
