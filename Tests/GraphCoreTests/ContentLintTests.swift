import Testing

@testable import GraphCore

/// Phase 9's authoring hints. Both halves matter: a rule that never fires is
/// decoration, and a rule that fires on good content teaches authors to ignore the
/// whole tool — which is worse than not shipping it. So every rule here is tested
/// against the thing it describes *and* against the hand-reviewed seed corpus,
/// which must stay clean.
@Suite("Authoring lint")
struct ContentLintTests {

    /// `Fixtures.clean` is a *graph* fixture: it carries ids, kinds and edges, and
    /// omits the prose, so `missing-statement` fires on almost every node in it and
    /// says nothing about the rule. It is dropped here and tested on its own in
    /// `aContentNodeWithNoStatementIsFlagged`.
    private func hints(_ nodes: [Node]) -> [LintHint] {
        ContentLint.hints(for: KnowledgeGraph(nodes: nodes)).filter {
            $0.rule != .missingStatement
        }
    }

    private func rules(_ nodes: [Node]) -> Set<LintHint.Rule> {
        Set(hints(nodes).map(\.rule))
    }

    /// `Fixtures.clean` is Appendix A, authored against the same checklist the lint
    /// encodes. Anything it flags is the rule being wrong, not the content.
    @Test func theSeedSubgraphIsClean() {
        let found = hints(Fixtures.clean)
        #expect(found.isEmpty, "\(found.map(\.description))")
    }

    @Test func anIsolatedNodeIsFlagged() {
        var nodes = Fixtures.clean
        nodes.append(
            Fixtures.content(
                "analysis.svc.island", .lemma, .detail, "Island",
                under: "analysis.svc", statement: "Nothing in the graph reaches this."))
        #expect(hints(nodes).filter { $0.rule == .isolatedNode }.map(\.subject) == ["analysis.svc.island"])
    }

    @Test func aDuplicateTitleAcrossBranchesIsFlagged() {
        var nodes = Fixtures.clean
        nodes.append(
            Fixtures.content(
                "foundations.real.mvt", .theorem, .standard, "Mean Value Theorem",
                under: "foundations.real", statement: "The same theorem, in another branch.",
                requires: ["foundations.real.sup-inf"]))
        let found = hints(nodes).filter { $0.rule == .duplicateTitle }
        #expect(found.count == 1)
        #expect(found.first?.nodes == ["analysis.svc.mvt", "foundations.real.mvt"])
    }

    @Test func anEmptySubbranchIsFlagged() {
        var nodes = Fixtures.clean
        nodes.append(Fixtures.subbranch("analysis.outlined", under: "analysis", "Outlined Only"))
        #expect(
            hints(nodes).filter { $0.rule == .emptySubbranch }.map(\.subject)
                == ["analysis.outlined"])
    }

    /// The integration tracker: a branch whose content never touches another
    /// branch's has not had §7.1's step-4 pass run on it.
    @Test func anUnintegratedBranchIsFlagged() {
        var nodes = Fixtures.clean
        nodes += [
            Fixtures.branch("island", "Island"),
            Fixtures.subbranch("island.one", under: "island", "One"),
            Fixtures.content(
                "island.one.a", .definition, .standard, "A", under: "island.one", statement: "A."),
            Fixtures.content(
                "island.one.b", .theorem, .standard, "B", under: "island.one", statement: "B.",
                requires: ["island.one.a"]),
        ]
        let found = hints(nodes).filter { $0.rule == .unintegratedBranch }
        #expect(found.map(\.subject) == ["island"])
    }

    @Test func aWidePrerequisiteFanIsFlagged() {
        var nodes = Fixtures.clean
        let seven = Fixtures.clean.filter { $0.kind.isContent }.prefix(7).map(\.id)
        nodes.append(
            Fixtures.content(
                "analysis.svc.bundle", .theorem, .standard, "Bundle", under: "analysis.svc",
                statement: "Needs everything at once.", requires: Array(seven)))
        #expect(
            hints(nodes).filter { $0.rule == .widePrerequisiteFan }.map(\.subject)
                == ["analysis.svc.bundle"])
    }

    @Test func aThinRelatesNoteIsFlagged() {
        var nodes = Fixtures.clean
        nodes.append(
            Fixtures.content(
                "analysis.svc.thin", .lemma, .detail, "Thin", under: "analysis.svc",
                statement: "x", requires: ["analysis.svc.def-limit"],
                relates: [RelatesRef(id: "analysis.svc.mvt", note: "see also")]))
        #expect(rules(nodes).contains(.thinRelatesNote))
    }

    @Test func aCompoundStatementIsFlagged() {
        var nodes = Fixtures.clean
        nodes.append(
            Fixtures.content(
                "analysis.svc.two-facts", .theorem, .standard, "Two facts", under: "analysis.svc",
                statement:
                    "Every continuous function on a closed bounded interval is bounded. "
                    + "Moreover, it attains its bounds.",
                requires: ["analysis.svc.def-continuity"]))
        #expect(rules(nodes).contains(.compoundStatement))
    }

    @Test func aFileOfLandmarksIsFlagged() {
        var nodes = Fixtures.clean
        nodes.append(Fixtures.subbranch("analysis.inflated", under: "analysis", "Inflated"))
        for index in 0..<4 {
            nodes.append(
                Fixtures.content(
                    NodeID("analysis.inflated.n\(index)"), .theorem, .landmark, "Landmark \(index)",
                    under: "analysis.inflated", statement: "x",
                    requires: index == 0 ? ["analysis.svc.mvt"] : [NodeID("analysis.inflated.n0")]))
        }
        #expect(
            hints(nodes).filter { $0.rule == .landmarkInflation }.map(\.subject)
                == ["analysis.inflated"])
    }

    /// The oversize threshold is relative to the corpus, so it cannot fire on a
    /// corpus of uniformly long statements — only on an outlier within one.
    @Test func onlyAnOutlierStatementIsFlaggedAsOversized() {
        #expect(!rules(Fixtures.clean).contains(.oversizedStatement))
        var nodes = Fixtures.clean
        nodes.append(
            Fixtures.content(
                "analysis.svc.enormous", .theorem, .standard, "Enormous", under: "analysis.svc",
                statement: String(repeating: "This says a great deal. ", count: 120),
                requires: ["analysis.svc.mvt"]))
        #expect(
            hints(nodes).filter { $0.rule == .oversizedStatement }.map(\.subject)
                == ["analysis.svc.enormous"])
    }

    @Test func aContentNodeWithNoStatementIsFlagged() {
        let nodes = [
            Fixtures.branch("analysis", "Analysis"),
            Fixtures.subbranch("analysis.svc", under: "analysis", "Single-Variable Calculus"),
            Fixtures.content(
                "analysis.svc.spoken", .definition, .standard, "Spoken", under: "analysis.svc",
                statement: "This one says something."),
            Fixtures.content(
                "analysis.svc.silent", .definition, .standard, "Silent", under: "analysis.svc",
                requires: ["analysis.svc.spoken"]),
        ]
        let found = ContentLint.hints(for: KnowledgeGraph(nodes: nodes))
            .filter { $0.rule == .missingStatement }
        #expect(found.map(\.subject) == ["analysis.svc.silent"])
    }
}
