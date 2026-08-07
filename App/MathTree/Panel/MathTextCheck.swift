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
            if (text.contains("{") || text.contains("}")), !source.contains("\\{"),
                !source.contains("\\}")
            {
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
            for sample in samples where sample.field == "statement" {
                lines.append("### \(sample.id)")
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

        /// Debug entry point. Wire it to a launch flag or call it from a breakpoint:
        ///
        ///     print(MathText.Check.report(for: try GraphDocument.load()))
        static func report(for document: GraphDocument) -> String {
            report(for: samples(for: document))
        }
    }

#endif
