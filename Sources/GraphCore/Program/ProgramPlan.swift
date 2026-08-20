import Foundation

/// §6.6's program, computed for one user at one instant: the authored spine
/// crossed with the graph and the score state. Everything the reader shows —
/// step order, met flags, the resume point, every progress number — is derived
/// here, in the testable module, exactly as `FocusPlan` is; the app contributes
/// spacing, colour and interaction.
///
/// The program keeps no state of its own: this is a pure fold over the same
/// evidence log every other read-out uses, so reading a lesson and reporting it
/// are the same acts they are everywhere else.
public struct ProgramPlan: Hashable, Sendable {
    /// One content node in teaching order.
    public struct Step: Hashable, Sendable, Identifiable {
        public let id: NodeID
        /// The unit that teaches it — its primary parent.
        public let unit: NodeID
        /// The frontier's exact notion (§4.5): learned *and* above τ right now.
        public let isMet: Bool
        /// Ever successfully retrieved (D8.3's reading). `isMet` implies this;
        /// learned-but-not-met is *decayed*, which the reader surfaces without
        /// letting it move the bookmark (see `resume`).
        public let isLearned: Bool

        public var isDecayed: Bool { isLearned && !isMet }

        public init(id: NodeID, unit: NodeID, isMet: Bool, isLearned: Bool) {
            self.id = id
            self.unit = unit
            self.isMet = isMet
            self.isLearned = isLearned
        }
    }

    /// One chapter: a subbranch's content nodes in a valid topological order of
    /// the `requires` relation restricted to the unit. That restriction is
    /// *complete* — precedence never arrives from a later unit — because the
    /// validator holds the spine to a linear extension of cross-unit `requires`.
    public struct Unit: Hashable, Sendable, Identifiable {
        public let id: NodeID
        /// Position over the whole program, 0-based; display adds one.
        public let index: Int
        public let steps: [Step]

        public init(id: NodeID, index: Int, steps: [Step]) {
            self.id = id
            self.index = index
            self.steps = steps
        }

        /// §7.1 fixes the outline before the content; an outlined-but-unwritten
        /// unit has no steps, which is a true state the reader words rather
        /// than draws.
        public var isAuthored: Bool { !steps.isEmpty }

        public var metCount: Int { steps.count(where: \.isMet) }
        public var learnedCount: Int { steps.count(where: \.isLearned) }
        public var isComplete: Bool { isAuthored && metCount == steps.count }
    }

    public struct Part: Hashable, Sendable {
        public let title: String
        public let units: [Unit]

        public init(title: String, units: [Unit]) {
            self.title = title
            self.units = units
        }
    }

    public let parts: [Part]

    /// The bookmark: the first step in program order that has **never been
    /// learned** — deliberately not the first *unmet* step. A program position
    /// means "where I got to", and one decayed foundations node must not yank it
    /// from unit 40 back to unit 3; decay surfaces through the due list and
    /// through compression un-compressing, never by moving the bookmark.
    public let resume: Step?

    public init(parts: [Part]) {
        self.parts = parts
        resume = parts.lazy
            .flatMap(\.units).flatMap(\.steps)
            .first { !$0.isLearned }
    }

    public var units: [Unit] { parts.flatMap(\.units) }
    public var steps: [Step] { units.flatMap(\.steps) }

    public var stepCount: Int { units.reduce(0) { $0 + $1.steps.count } }
    public var metCount: Int { units.reduce(0) { $0 + $1.metCount } }

    public func unit(_ id: NodeID) -> Unit? {
        units.first { $0.id == id }
    }

    /// Where a node sits in the program, for "read the lesson" jumps from the
    /// map. `nil` for anything the program does not teach — structural nodes,
    /// and content whose home subbranch is (invalidly) off the spine.
    public func step(for node: NodeID) -> Step? {
        steps.first { $0.id == node }
    }

    // MARK: - Computation

    public static func compute(
        spine: ProgramSpine,
        graph: KnowledgeGraph,
        state: ScoreState,
        at now: Date,
        config: ScoringConfig = ScoringConfig()
    ) -> ProgramPlan {
        let fsrs = FSRS(parameters: config.fsrs)
        func isMet(_ id: NodeID) -> Bool {
            guard state.isLearned(id), let memory = state.nodes[id] else { return false }
            return fsrs.retrievability(of: memory, at: now) > config.masteryThreshold
        }

        var index = 0
        var parts: [Part] = []
        for part in spine.parts {
            var units: [Unit] = []
            for unit in part.units {
                units.append(
                    Unit(
                        id: unit, index: index,
                        steps: order(unit: unit, graph: graph).map {
                            Step(
                                id: $0, unit: unit,
                                isMet: isMet($0), isLearned: state.isLearned($0))
                        }))
                index += 1
            }
            parts.append(Part(title: part.title, units: units))
        }
        return ProgramPlan(parts: parts)
    }

    /// Teaching order within one unit: membership is the unit's *primary*
    /// children (a node is taught once, where it lives — `also_under` cross-
    /// listings stay a subject-path concern, D11.2), order is (layer, id) with
    /// layers by longest path over the unit's own `requires` edges — the same
    /// construction as `FocusPlan`'s, for the same reason: any directed path
    /// strictly increases the layer, so (layer, id) is a valid topological order.
    private static func order(unit: NodeID, graph: KnowledgeGraph) -> [NodeID] {
        let members = Set(
            graph.children(of: unit).filter { graph[$0]?.kind.isContent == true })

        var layer: [NodeID: Int] = [:]
        func layerOf(_ id: NodeID) -> Int {
            if let known = layer[id] { return known }
            // Marked before recursing so an (invalid, validator-rejected) cycle
            // terminates instead of recursing forever.
            layer[id] = 0
            let prerequisites = graph.prerequisites(of: id).filter { members.contains($0) }
            let value = prerequisites.map { layerOf($0) + 1 }.max() ?? 0
            layer[id] = value
            return value
        }
        for id in members.sorted() { _ = layerOf(id) }

        return members.sorted { (layer[$0]!, $0) < (layer[$1]!, $1) }
    }
}
