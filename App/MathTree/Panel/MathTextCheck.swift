import Foundation

extension MathText {

    /// A self-check over the corpus, because the panel cannot be screenshotted.
    ///
    /// This catches the *mechanical* failures of a LaTeX-lite renderer — a macro that was
    /// never consumed, a math span that was never closed, a statement that rendered to
    /// nothing. It deliberately makes no claim about whether the output reads well; that
    /// judgement is made by printing `plainText` for every statement and reading it.
    ///
    /// `Foundation` only and `GraphCore`-free on purpose, so it can be compiled and run
    /// standalone against `graph.json` without linking the app.
    enum Check {

        struct Sample: Sendable {
            var id: String
            var field: String
            var source: String

            init(id: String, field: String, source: String) {
                self.id = id
                self.field = field
                self.source = source
            }
        }

        struct Finding: Equatable, Sendable, CustomStringConvertible {
            var id: String
            var field: String
            var issue: String
            var rendered: String

            var description: String { "\(id) [\(field)]: \(issue)\n      → \(rendered)" }
        }

        static func findings(in samples: [Sample]) -> [Finding] {
            samples.flatMap { findings(in: $0) }
        }

        static func findings(in sample: Sample) -> [Finding] {
            let source = sample.source
            let rendered = MathText.render(source)
            let text = rendered.plainText
            var found: [Finding] = []

            func report(_ issue: String) {
                found.append(
                    Finding(id: sample.id, field: sample.field, issue: issue, rendered: text))
            }

            if unescapedDollarCount(in: source).isMultiple(of: 2) == false {
                report("unbalanced $ delimiters in source")
            }
            if text.contains("\\"), !source.contains("\\backslash") {
                report("leftover backslash — a macro was not consumed")
            }
            if text.contains("$") {
                report("unconsumed $ — a math delimiter reached the output")
            }
            if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rendered.isEmpty {
                report("empty rendering from non-empty source")
            }
            // "Grouping braces reached the output" has to mean braces the *renderer*
            // produced, not braces the author typed as prose. A title like
            // "ℚ as a quotient of ℤ × (ℤ ∖ {0})" is plain text with set-builder
            // braces in it, and outside a math span a brace is a character like any
            // other. So the rule counts: more braces out than the source typed
            // outside `$…$` means the renderer leaked one.
            let literal = source.contains("\\{") || source.contains("\\}")
            if !literal, braceCount(in: text) > textModeBraceCount(in: source) {
                report("stray brace — grouping braces reached the output")
            }
            if rendered.runs.contains(where: { $0.sizeMultiplier <= 0 }) {
                report("non-positive run size")
            }
            return found
        }

        /// The eyeball half of the check. Mechanical flags catch crashes; only reading the
        /// linearised statements catches ugliness, which is the bar Phase 4 actually sets
        /// ("the smallest thing that renders the seed content *acceptably*").
        static func report(for samples: [Sample]) -> String {
            var lines: [String] = []
            // Statements *and* answers: a problem's worked answer is where its
            // densest notation lives, and it is the surface a solver reads after a
            // failed attempt — printing only prompts would review half the corpus.
            for sample in samples where sample.field == "statement" || sample.field == "answer" {
                lines.append("### \(sample.id) [\(sample.field)]")
                lines.append(
                    MathText.plainText(sample.source)
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
            let found = findings(in: samples)
            if found.isEmpty {
                lines.append("self-check: clean over \(samples.count) fields")
            } else {
                lines.append("self-check: \(found.count) finding(s)")
                lines.append(contentsOf: found.map { "  " + $0.description })
            }
            return lines.joined(separator: "\n")
        }

        private static func braceCount(in text: String) -> Int {
            text.reduce(0) { $0 + (($1 == "{" || $1 == "}") ? 1 : 0) }
        }

        /// Braces the author typed outside any `$…$` span, where the renderer has no
        /// grouping semantics and a brace is just a character.
        private static func textModeBraceCount(in source: String) -> Int {
            var count = 0
            var inMath = false
            var escaped = false
            for character in source {
                if escaped {
                    escaped = false
                    continue
                }
                switch character {
                case "\\": escaped = true
                case "$": inMath.toggle()
                case "{", "}": if !inMath { count += 1 }
                default: break
                }
            }
            return count
        }

        private static func unescapedDollarCount(in source: String) -> Int {
            var count = 0
            var escaped = false
            for character in source {
                if escaped {
                    escaped = false
                    continue
                }
                if character == "\\" {
                    escaped = true
                    continue
                }
                if character == "$" { count += 1 }
            }
            return count
        }
    }
}

// `canImport` rather than a bare `import`: this file is also compiled standalone, with no
// GraphCore in the search path, so that the renderer can be exercised against `graph.json`
// without linking the app.
#if DEBUG && canImport(GraphCore)

    import GraphCore

    extension MathText.Check {
        /// Every renderable field of every node in the loaded corpus.
        static func samples(for document: GraphDocument) -> [Sample] {
            document.nodes.flatMap { node -> [Sample] in
                var samples = [
                    Sample(id: node.id.rawValue, field: "title", source: node.title)
                ]
                if let statement = node.statement {
                    samples.append(
                        Sample(id: node.id.rawValue, field: "statement", source: statement))
                }
                if let summary = node.summary {
                    samples.append(Sample(id: node.id.rawValue, field: "summary", source: summary))
                }
                samples.append(
                    contentsOf: node.relates.map {
                        Sample(id: node.id.rawValue, field: "relates.note", source: $0.note)
                    })
                return samples
            }
        }

        /// Every renderable field of every problem in the bank (§5.2).
        ///
        /// The bank roughly doubled the corpus's LaTeX-bearing text — statements,
        /// worked answers, and every rubric criterion — and none of it appears in
        /// any node. Reviewing it means running the same check over it; the
        /// alternative is trusting that ninety hand-written fields all render,
        /// which D4.10 already showed is not a safe assumption.
        static func samples(for bank: ProblemBank) -> [Sample] {
            bank.problems.flatMap { problem -> [Sample] in
                [
                    Sample(id: problem.id.rawValue, field: "statement", source: problem.statement),
                    Sample(id: problem.id.rawValue, field: "answer", source: problem.answer),
                ]
                    + problem.rubric.enumerated().map {
                        Sample(
                            id: problem.id.rawValue, field: "rubric[\($0.offset)]",
                            source: $0.element)
                    }
            }
        }

        /// Debug entry point. `MATHTREE_MATH_CHECK=1` runs it at launch and exits;
        /// it can also be called from a breakpoint:
        ///
        ///     print(MathText.Check.report(for: try GraphDocument.load()))
        static func report(for document: GraphDocument) -> String {
            report(for: samples(for: document))
        }

        /// Both corpora in one pass, with the `statement` read-out that has to be
        /// *read* rather than merely passed (see `report(for:)`'s note).
        ///
        /// Environment-driven per D3.7: AppKit parses stray `--flag value` pairs
        /// into `NSUserDefaults` and the window silently never appears.
        @MainActor
        static func runIfRequested(document: GraphDocument, problems: ProblemDocument) {
            guard ProcessInfo.processInfo.environment["MATHTREE_MATH_CHECK"] == "1" else { return }
            let samples = samples(for: document) + samples(for: problems.bank)
            print(report(for: samples))
            if let reason = problems.unavailable {
                print("note: problem bank not checked — \(reason)")
            }
            fflush(stdout)
            exit(findings(in: samples).isEmpty ? 0 : 1)
        }
    }

#endif
