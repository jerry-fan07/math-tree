import Testing

@testable import GraphCore

/// Each broken case is the smallest graph that trips its rule. Assertions check for
/// the presence of `(rule, offending ids)` rather than an exact diagnostic count —
/// one authoring mistake legitimately violates several invariants at once.
@Suite("Validator")
struct ValidatorTests {
    // branch → subbranch → two theorems, plus a spare subbranch for parent games.
    static func base() -> [Node] {
        [
            Fixtures.branch("a", "A"),
            Fixtures.subbranch("a.b", under: "a", "B"),
            Fixtures.subbranch("a.c", under: "a", "C"),
            Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b"),
            Fixtures.content("a.b.y", .theorem, .standard, "Y", under: "a.b"),
        ]
    }

    /// Replace the node with the given id, keeping everything else.
    static func graph(replacing id: NodeID, with node: Node) -> [Diagnostic] {
        GraphValidator.validate(nodes: base().filter { $0.id != id } + [node])
    }

    /// The skeleton plus a hand-written set of content nodes under `a.b`.
    static func graph(content nodes: [Node]) -> [Diagnostic] {
        GraphValidator.validate(nodes: base().filter { $0.kind.isStructural } + nodes)
    }

    // MARK: The clean cases

    @Test func appendixAFixtureIsClean() {
        let diagnostics = GraphValidator.validate(nodes: Fixtures.clean)
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.description))")
    }

    @Test func otherFixturesAreClean() {
        #expect(GraphValidator.validate(nodes: Fixtures.diamond).isEmpty)
        #expect(GraphValidator.validate(nodes: Fixtures.chain(length: 25)).isEmpty)
        #expect(GraphValidator.validate(nodes: Self.base()).isEmpty)
    }

    @Test func diagnosticsComeBackSorted() {
        var nodes = Self.base()
        nodes.append(Fixtures.content("a.b.BAD", .theorem, .standard, "", under: "a.b"))
        nodes.append(Fixtures.content("a.b.z", .theorem, .standard, "Z", under: "a.b",
                                      requires: ["a.b.nope"]))
        let diagnostics = GraphValidator.validate(nodes: nodes)
        #expect(diagnostics == diagnostics.sorted())
        #expect(diagnostics.count > 2)
    }

    // MARK: Identity

    @Test func duplicateIDsAreReported() {
        var nodes = Self.base()
        nodes.append(Fixtures.content("a.b.x", .lemma, .detail, "X again", under: "a.b"))
        let diagnostics = GraphValidator.validate(nodes: nodes)
        #expect(diagnostics.has(.duplicateID, "a.b.x"))
    }

    @Test func idsMustBeLowercaseKebab() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.Bad_Slug", .theorem, .standard, "X", under: "a.b")
        )
        #expect(diagnostics.has(.malformedID, "a.b.Bad_Slug"))

        for bad: NodeID in ["a.b.-lead", "a.b.trail-", "a.b.double--hyphen", "a.b."] {
            let out = Self.graph(
                replacing: "a.b.x",
                with: Fixtures.content(bad, .theorem, .standard, "X", under: "a.b")
            )
            #expect(out.has(.malformedID, bad), "expected \(bad) to be rejected")
        }
        #expect(GraphValidator.isKebabComponent("ftc-2"))
        #expect(GraphValidator.isKebabComponent("sup-inf"))
    }

    @Test func componentCountIsFixedByKind() {
        // A subbranch with three components, and a theorem with two.
        let diagnostics = GraphValidator.validate(nodes: [
            Fixtures.branch("a", "A"),
            Fixtures.subbranch("a.b.c", under: "a", "Too deep"),
            Fixtures.content("a.d", .theorem, .standard, "Too shallow", under: "a"),
        ])
        #expect(diagnostics.has(.malformedID, "a.b.c"))
        #expect(diagnostics.has(.malformedID, "a.d"))
    }

    @Test func idMustExtendItsPrimaryParent() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.c")
        )
        #expect(diagnostics.has(.idParentPrefixMismatch, "a.b.x", "a.c"))
    }

    @Test func crossListingsDoNotNeedTheIDPrefix() {
        // The mirror image of the previous test: `also_under` is exempt by design.
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   alsoUnder: ["a.c"])
        )
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.description))")
    }

    @Test func titlesAreRequired() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "   ", under: "a.b")
        )
        #expect(diagnostics.has(.emptyTitle, "a.b.x"))
    }

    // MARK: Contains structure

    @Test func nonBranchNodesNeedAPrimaryParent() {
        let diagnostics = GraphValidator.validate(nodes: [
            Fixtures.branch("a", "A"),
            Node(id: "a.b", kind: .subbranch, title: "B"),
        ])
        #expect(diagnostics.has(.missingPrimaryParent, "a.b"))
    }

    @Test func branchNodesMustNotHaveAParent() {
        var nodes = Self.base()
        nodes.append(Node(id: "z", kind: .branch, title: "Z", parent: "a"))
        let diagnostics = GraphValidator.validate(nodes: nodes)
        #expect(diagnostics.has(.unexpectedPrimaryParent, "z", "a"))
    }

    @Test func primaryParentMustBeOneLevelUp() {
        // `a.b` keeps its id but is authored as a content kind, so `a.b.x`'s parent
        // is no longer a subbranch.
        let diagnostics = Self.graph(
            replacing: "a.b",
            with: Fixtures.content("a.b", .definition, .standard, "Not a subbranch", under: "a")
        )
        #expect(diagnostics.has(.primaryParentKindMismatch, "a.b.x", "a.b"))
        #expect(diagnostics.has(.primaryParentKindMismatch, "a.b.y", "a.b"))
    }

    @Test func nodesCannotContainThemselves() {
        let viaParent = Self.graph(
            replacing: "a.b.x",
            with: Node(id: "a.b.x", kind: .theorem, title: "X", parent: "a.b.x")
        )
        #expect(viaParent.has(.selfContains, "a.b.x"))

        let viaAlsoUnder = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   alsoUnder: ["a.b.x"])
        )
        #expect(viaAlsoUnder.has(.selfContains, "a.b.x"))
    }

    @Test func primaryParentCyclesAreReportedWithTheirPath() {
        let diagnostics = GraphValidator.validate(nodes: [
            Fixtures.branch("a", "A"),
            Fixtures.subbranch("a.b", under: "a.c", "B"),
            Fixtures.subbranch("a.c", under: "a.b", "C"),
        ])
        #expect(diagnostics.has(.containsCycle, "a.b", "a.c"))
        let cycle = diagnostics.rules(.containsCycle).first
        #expect(cycle?.nodes == ["a.b", "a.c"])
        #expect(cycle?.path == ["a.b", "a.c", "a.b"])
    }

    @Test func alsoUnderRejectsDuplicatesAndThePrimaryParent() {
        let duplicated = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   alsoUnder: ["a.c", "a.c"])
        )
        #expect(duplicated.has(.duplicateAlsoUnder, "a.b.x", "a.c"))

        let repeated = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   alsoUnder: ["a.b"])
        )
        #expect(repeated.has(.alsoUnderRepeatsPrimaryParent, "a.b.x", "a.b"))
    }

    @Test func alsoUnderTargetsMustBeStructural() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   alsoUnder: ["a.b.y"])
        )
        #expect(diagnostics.has(.alsoUnderNotStructural, "a.b.x", "a.b.y"))
    }

    // MARK: Dangling references, per field

    @Test func danglingParentIsReported() {
        var nodes = Self.base()
        nodes.append(Fixtures.content("a.zz.x", .theorem, .standard, "X", under: "a.zz"))
        let diagnostics = GraphValidator.validate(nodes: nodes)
        #expect(diagnostics.has(.danglingParent, "a.zz.x", "a.zz"))
    }

    @Test func danglingAlsoUnderIsReported() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   alsoUnder: ["a.nope"])
        )
        #expect(diagnostics.has(.danglingAlsoUnder, "a.b.x", "a.nope"))
    }

    @Test func danglingRequiresIsReported() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   requires: ["a.b.nope"])
        )
        #expect(diagnostics.has(.danglingRequires, "a.b.x", "a.b.nope"))
    }

    @Test func danglingRelatesIsReported() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   relates: [RelatesRef(id: "a.b.nope", note: "n")])
        )
        #expect(diagnostics.has(.danglingRelates, "a.b.x", "a.b.nope"))
    }

    // MARK: Requires

    @Test func duplicateRequiresIsReported() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   requires: ["a.b.y", "a.b.y"])
        )
        #expect(diagnostics.has(.duplicateRequires, "a.b.x", "a.b.y"))
    }

    @Test func requiresCyclesReportTheirPathInOrder() {
        let diagnostics = Self.graph(content: [
            Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b", requires: ["a.b.z"]),
            Fixtures.content("a.b.y", .theorem, .standard, "Y", under: "a.b", requires: ["a.b.x"]),
            Fixtures.content("a.b.z", .theorem, .standard, "Z", under: "a.b", requires: ["a.b.y"]),
        ])
        #expect(diagnostics.has(.requiresCycle, "a.b.x", "a.b.y", "a.b.z"))
        let cycle = diagnostics.rules(.requiresCycle).first
        // Rotated to start at the smallest id; each step requires the next.
        #expect(cycle?.nodes == ["a.b.x", "a.b.z", "a.b.y"])
        #expect(cycle?.path == ["a.b.x", "a.b.z", "a.b.y", "a.b.x"])
    }

    @Test func selfRequiresIsACycleOfLengthOne() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   requires: ["a.b.x"])
        )
        #expect(diagnostics.has(.requiresCycle, "a.b.x"))
    }

    @Test func transitivelyImpliedRequiresEdgesAreRedundant() {
        // y already requires z, so x listing z as well is not the transitive reduction.
        let diagnostics = Self.graph(content: [
            Fixtures.content("a.b.z", .theorem, .standard, "Z", under: "a.b"),
            Fixtures.content("a.b.y", .theorem, .standard, "Y", under: "a.b",
                             requires: ["a.b.z"]),
            Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                             requires: ["a.b.y", "a.b.z"]),
        ])
        #expect(diagnostics.has(.redundantRequires, "a.b.x", "a.b.z"))
        #expect(diagnostics.rules(.redundantRequires).first?.path == ["a.b.x", "a.b.y", "a.b.z"])
    }

    @Test func redundancyIsFoundWhateverOrderThePrerequisitesSortIn() {
        // Same shape, but the redundant edge's target now sorts *before* the
        // prerequisite that reaches it.
        let diagnostics = Self.graph(content: [
            Fixtures.content("a.b.p", .theorem, .standard, "P", under: "a.b"),
            Fixtures.content("a.b.q", .theorem, .standard, "Q", under: "a.b",
                             requires: ["a.b.p"]),
            Fixtures.content("a.b.r", .theorem, .standard, "R", under: "a.b",
                             requires: ["a.b.p", "a.b.q"]),
        ])
        #expect(diagnostics.has(.redundantRequires, "a.b.r", "a.b.p"))
        #expect(diagnostics.rules(.redundantRequires).first?.path == ["a.b.r", "a.b.q", "a.b.p"])
    }

    @Test func transitiveReductionIsSkippedWhenACycleExists() {
        // A cycle makes "already an ancestor" meaningless; the run must not hang or
        // drown the real problem in noise.
        let diagnostics = Self.graph(content: [
            Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                             requires: ["a.b.y"]),
            Fixtures.content("a.b.y", .theorem, .standard, "Y", under: "a.b",
                             requires: ["a.b.x"]),
        ])
        #expect(diagnostics.has(.requiresCycle, "a.b.x", "a.b.y"))
        #expect(diagnostics.rules(.redundantRequires).isEmpty)
    }

    // MARK: Structural purity

    @Test func structuralNodesCarryNoContentFields() {
        let diagnostics = Self.graph(
            replacing: "a.b",
            with: Node(
                id: "a.b",
                kind: .subbranch,
                title: "B",
                statement: "structural nodes are not knowledge",
                parent: "a",
                requires: ["a.c"],
                relates: [RelatesRef(id: "a.c", note: "n")]
            )
        )
        #expect(diagnostics.has(.structuralNodeHasStatement, "a.b"))
        #expect(diagnostics.has(.structuralNodeHasRequires, "a.b"))
        #expect(diagnostics.has(.structuralNodeHasRelates, "a.b"))
    }

    // MARK: Relates

    @Test func selfRelatesIsReported() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   relates: [RelatesRef(id: "a.b.x", note: "n")])
        )
        #expect(diagnostics.has(.selfRelates, "a.b.x"))
    }

    @Test func relatesNotesAreRequired() {
        let diagnostics = Self.graph(
            replacing: "a.b.x",
            with: Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                                   relates: [RelatesRef(id: "a.b.y", note: " ")])
        )
        #expect(diagnostics.has(.emptyRelatesNote, "a.b.x", "a.b.y"))
    }

    @Test func aConnectionAuthoredFromBothEndsIsADuplicate() {
        let diagnostics = Self.graph(content: [
            Fixtures.content("a.b.x", .theorem, .standard, "X", under: "a.b",
                             relates: [RelatesRef(id: "a.b.y", note: "n")]),
            Fixtures.content("a.b.y", .theorem, .standard, "Y", under: "a.b",
                             relates: [RelatesRef(id: "a.b.x", note: "n")]),
        ])
        #expect(diagnostics.has(.duplicateRelates, "a.b.x", "a.b.y"))
    }

    @Test func everyRuleHasAStableSlug() {
        // Guards against two cases sharing a raw value after a rename.
        let slugs = DiagnosticRule.allCases.map(\.rawValue)
        #expect(Set(slugs).count == slugs.count)
    }
}
