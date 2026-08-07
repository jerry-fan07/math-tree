@testable import GraphCore

/// Hand-built graphs the tests reason about directly. `clean` is a faithful subset of
/// design.md Appendix A, so a change that breaks real content breaks a test.
enum Fixtures {
    static func branch(_ id: NodeID, _ title: String) -> Node {
        Node(id: id, kind: .branch, title: title)
    }

    static func subbranch(_ id: NodeID, under parent: NodeID, _ title: String) -> Node {
        Node(id: id, kind: .subbranch, title: title, parent: parent)
    }

    static func content(
        _ id: NodeID,
        _ kind: NodeKind,
        _ prominence: Prominence,
        _ title: String,
        under parent: NodeID,
        statement: String? = nil,
        alsoUnder: [NodeID] = [],
        requires: [NodeID] = [],
        relates: [RelatesRef] = []
    ) -> Node {
        Node(
            id: id,
            kind: kind,
            prominence: prominence,
            title: title,
            statement: statement,
            parent: parent,
            alsoUnder: alsoUnder,
            requires: requires,
            relates: relates
        )
    }

    /// Appendix A's single-variable-calculus → FTC subgraph, with the Foundations
    /// nodes it depends on. Must validate with zero diagnostics.
    static let clean: [Node] = [
        branch("foundations", "Foundations"),
        subbranch("foundations.real", under: "foundations", "The Real Numbers"),
        content(
            "foundations.real.sup-inf", .definition, .standard, "Supremum and infimum",
            under: "foundations.real",
            statement: "The least upper bound and greatest lower bound of a subset of $\\mathbb{R}$."
        ),
        content(
            "foundations.real.completeness", .axiom, .standard, "Completeness axiom of ℝ",
            under: "foundations.real",
            statement: "Every nonempty subset of $\\mathbb{R}$ bounded above has a supremum in $\\mathbb{R}$.",
            requires: ["foundations.real.sup-inf"]
        ),

        branch("analysis", "Analysis"),
        subbranch("analysis.svc", under: "analysis", "Single-Variable Calculus"),
        subbranch("analysis.mvc", under: "analysis", "Multivariable Calculus"),

        content(
            "analysis.svc.def-limit", .definition, .landmark, "ε–δ limit of a function",
            under: "analysis.svc",
            statement: "$\\lim_{x\\to a} f(x) = L$ iff for every $\\varepsilon>0$ there is $\\delta>0$ …",
            requires: ["foundations.real.sup-inf"]
        ),
        content(
            "analysis.svc.def-continuity", .definition, .standard, "Continuity at a point",
            under: "analysis.svc",
            requires: ["analysis.svc.def-limit"]
        ),
        content(
            "analysis.svc.evt", .theorem, .standard, "Extreme Value Theorem",
            under: "analysis.svc",
            requires: ["analysis.svc.def-continuity", "foundations.real.completeness"]
        ),
        content(
            "analysis.svc.ivt", .theorem, .standard, "Intermediate Value Theorem",
            under: "analysis.svc",
            requires: ["analysis.svc.def-continuity", "foundations.real.completeness"],
            relates: [RelatesRef(
                id: "analysis.svc.evt",
                note: "Both extract a global conclusion on [a,b] from continuity plus completeness."
            )]
        ),
        content(
            "analysis.svc.def-derivative", .definition, .landmark, "Derivative at a point",
            under: "analysis.svc",
            requires: ["analysis.svc.def-limit"]
        ),
        content(
            "analysis.svc.intuition-linearization", .intuition, .detail,
            "Derivative as local linear approximation",
            under: "analysis.svc",
            requires: ["analysis.svc.def-derivative"]
        ),
        content(
            "analysis.svc.diff-implies-cont", .lemma, .detail, "Differentiability ⇒ continuity",
            under: "analysis.svc",
            requires: ["analysis.svc.def-continuity", "analysis.svc.def-derivative"]
        ),
        content(
            "analysis.svc.rolle", .lemma, .detail, "Rolle's Theorem",
            under: "analysis.svc",
            requires: ["analysis.svc.diff-implies-cont", "analysis.svc.evt"]
        ),
        content(
            "analysis.svc.mvt", .theorem, .standard, "Mean Value Theorem",
            under: "analysis.svc",
            requires: ["analysis.svc.rolle"],
            relates: [RelatesRef(
                id: "analysis.mvc.leibniz-rule",
                note: "Both reduce a statement about an interval to a single derivative value."
            )]
        ),
        content(
            "analysis.svc.zero-deriv-const", .corollary, .detail, "f′ ≡ 0 ⇒ f constant",
            under: "analysis.svc",
            requires: ["analysis.svc.mvt"]
        ),
        content(
            "analysis.svc.def-riemann-sum", .definition, .detail, "Riemann sum",
            under: "analysis.svc",
            requires: ["foundations.real.sup-inf"]
        ),
        content(
            "analysis.svc.def-riemann-integral", .definition, .standard, "Riemann integral",
            under: "analysis.svc",
            requires: ["analysis.svc.def-riemann-sum"]
        ),
        content(
            "analysis.svc.cont-integrable", .proposition, .detail,
            "Continuous on [a,b] ⇒ integrable",
            under: "analysis.svc",
            requires: ["analysis.svc.def-continuity", "analysis.svc.def-riemann-integral"]
        ),
        content(
            "analysis.svc.ex-integral-x2", .example, .detail, "∫₀¹ x² dx from Riemann sums",
            under: "analysis.svc",
            requires: ["analysis.svc.def-riemann-integral"]
        ),
        content(
            "analysis.svc.def-antiderivative", .definition, .detail, "Antiderivative",
            under: "analysis.svc",
            requires: ["analysis.svc.def-derivative"]
        ),
        content(
            "analysis.svc.ftc-1", .theorem, .landmark, "FTC, Part I",
            under: "analysis.svc",
            requires: ["analysis.svc.cont-integrable", "analysis.svc.def-antiderivative"]
        ),
        content(
            "analysis.svc.ftc-2", .theorem, .landmark, "FTC, Part II",
            under: "analysis.svc",
            statement: "If $f$ is continuous on $[a,b]$ and $F$ is any antiderivative of $f$, "
                + "then $\\int_a^b f(x)\\,dx = F(b) - F(a)$.",
            requires: ["analysis.svc.ftc-1", "analysis.svc.zero-deriv-const"]
        ),
        content(
            "analysis.svc.u-sub", .technique, .standard, "u-substitution",
            under: "analysis.svc",
            requires: ["analysis.svc.ftc-2"]
        ),

        // Cross-listed: lives in Multivariable, surfaces under Single-Variable too (§2.3).
        content(
            "analysis.mvc.leibniz-rule", .theorem, .standard, "Leibniz integral rule",
            under: "analysis.mvc",
            alsoUnder: ["analysis.svc"],
            requires: ["analysis.svc.def-derivative"]
        ),
    ]

    /// a ← {b, c} ← d: the smallest graph that proves ancestor dedup.
    static let diamond: [Node] = [
        branch("d", "Diamond"),
        subbranch("d.s", under: "d", "Sub"),
        content("d.s.a", .definition, .standard, "A", under: "d.s"),
        content("d.s.b", .theorem, .standard, "B", under: "d.s", requires: ["d.s.a"]),
        content("d.s.c", .theorem, .standard, "C", under: "d.s", requires: ["d.s.a"]),
        content("d.s.d", .theorem, .standard, "D", under: "d.s", requires: ["d.s.b", "d.s.c"]),
    ]

    /// `length` content nodes in a single `requires` chain, deepest last.
    static func chain(length: Int) -> [Node] {
        var nodes: [Node] = [
            branch("synthetic", "Synthetic"),
            subbranch("synthetic.chain", under: "synthetic", "Chain"),
        ]
        nodes.reserveCapacity(length + 2)
        for step in 0..<length {
            nodes.append(content(
                chainStep(step), .lemma, .detail, "Step \(step)",
                under: "synthetic.chain",
                requires: step == 0 ? [] : [chainStep(step - 1)]
            ))
        }
        return nodes
    }

    static func chainStep(_ step: Int) -> NodeID {
        // Zero-padded so ids sort in chain order, which makes failures readable.
        var digits = String(step)
        while digits.count < 5 { digits = "0" + digits }
        return NodeID("synthetic.chain.step-\(digits)")
    }
}

extension [Diagnostic] {
    /// Broken fixtures usually trip more than one rule; assert presence, never count.
    func has(_ rule: DiagnosticRule, _ ids: NodeID...) -> Bool {
        contains { diagnostic in
            diagnostic.rule == rule && ids.allSatisfy(diagnostic.nodes.contains)
        }
    }

    func rules(_ rule: DiagnosticRule) -> [Diagnostic] {
        filter { $0.rule == rule }
    }
}
