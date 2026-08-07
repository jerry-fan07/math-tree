/// Enforces the content invariants of §3.3 (plus the ones §2.1–§2.3 state in prose)
/// over an already-loaded graph. Never throws and never stops at the first problem:
/// authors want the whole list, and Phase 2's CLI wants to annotate every one.
public enum GraphValidator {
    public static func validate(nodes: [Node]) -> [Diagnostic] {
        validate(KnowledgeGraph(nodes: nodes))
    }

    public static func validate(_ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        out += duplicateIDs(graph)
        out += perNodeChecks(graph)
        out += containsCycles(graph)
        out += duplicateRelates(graph)

        let cycles = requiresCycles(graph)
        out += cycles.map { cycle in
            Diagnostic(
                rule: .requiresCycle,
                message: "`requires` cycle: \(closedPath(cycle))",
                nodes: cycle,
                path: cycle + [cycle[0]]
            )
        }
        // Transitive reduction assumes acyclicity; on a cyclic graph "already an
        // ancestor" is meaningless and the traversal would just report noise.
        if cycles.isEmpty {
            out += redundantRequires(graph)
        }

        out.sort()
        return out
    }

    // MARK: Identity

    private static func duplicateIDs(_ graph: KnowledgeGraph) -> [Diagnostic] {
        var counts: [NodeID: Int] = [:]
        for node in graph.nodes { counts[node.id, default: 0] += 1 }
        return counts.filter { $0.value > 1 }
            .sorted { $0.key < $1.key }
            .map { id, count in
                Diagnostic(
                    rule: .duplicateID,
                    message: "id `\(id)` is declared \(count) times; ids must be unique",
                    nodes: [id]
                )
            }
    }

    /// `[a-z0-9]+(-[a-z0-9]+)*` — lowercase kebab, no leading/trailing/doubled hyphen.
    static func isKebabComponent(_ component: Substring) -> Bool {
        if component.isEmpty { return false }
        var afterHyphen = true
        for character in component {
            if character == "-" {
                if afterHyphen { return false }
                afterHyphen = true
            } else if character.isASCII, character.isLowercase || character.isNumber {
                afterHyphen = false
            } else {
                return false
            }
        }
        return !afterHyphen
    }

    // MARK: Per-node checks

    private static func perNodeChecks(_ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for node in graph.nodes {
            out += idFormat(node)
            out += titleShape(node)
            out += parenting(node, graph)
            out += alsoUnder(node, graph)
            out += requires(node, graph)
            out += relates(node, graph)
            out += structuralPurity(node)
        }
        return out
    }

    private static func idFormat(_ node: Node) -> [Diagnostic] {
        let components = node.id.components
        let expected = node.kind.idComponentCount
        if components.count != expected {
            return [Diagnostic(
                rule: .malformedID,
                message: "a `\(node.kind.rawValue)` id needs \(expected) dot-separated component(s), "
                    + "`\(node.id)` has \(components.count)",
                nodes: [node.id]
            )]
        }
        if let bad = components.first(where: { !isKebabComponent($0) }) {
            return [Diagnostic(
                rule: .malformedID,
                message: "id component `\(bad)` is not lowercase-kebab ([a-z0-9] separated by single hyphens)",
                nodes: [node.id]
            )]
        }
        return []
    }

    private static func titleShape(_ node: Node) -> [Diagnostic] {
        node.title.allSatisfy(\.isWhitespace)
            ? [Diagnostic(rule: .emptyTitle, message: "node has no title", nodes: [node.id])]
            : []
    }

    private static func parenting(_ node: Node, _ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        guard let parent = node.parent else {
            if node.kind != .branch {
                out.append(Diagnostic(
                    rule: .missingPrimaryParent,
                    message: "a `\(node.kind.rawValue)` node needs exactly one primary `parent`",
                    nodes: [node.id]
                ))
            }
            return out
        }
        if node.kind == .branch {
            out.append(Diagnostic(
                rule: .unexpectedPrimaryParent,
                message: "`branch` nodes are taxonomy roots and must not declare a parent",
                nodes: [node.id, parent]
            ))
            return out
        }
        if parent == node.id {
            out.append(Diagnostic(
                rule: .selfContains,
                message: "node is its own `contains` parent",
                nodes: [node.id]
            ))
            return out
        }
        // Primary parents own the id prefix; `also_under` cross-listings do not (§2.3).
        if node.id.parentPrefix != parent {
            out.append(Diagnostic(
                rule: .idParentPrefixMismatch,
                message: "id `\(node.id)` must be its primary parent `\(parent)` plus one component",
                nodes: [node.id, parent]
            ))
        }
        guard let parentNode = graph[parent] else {
            out.append(Diagnostic(
                rule: .danglingParent,
                message: "`parent` references unknown node `\(parent)`",
                nodes: [node.id, parent]
            ))
            return out
        }
        if parentNode.kind != node.kind.primaryParentKind {
            let expected = node.kind.primaryParentKind?.rawValue ?? "none"
            out.append(Diagnostic(
                rule: .primaryParentKindMismatch,
                message: "a `\(node.kind.rawValue)` node's primary parent must be a `\(expected)`, "
                    + "but `\(parent)` is a `\(parentNode.kind.rawValue)`",
                nodes: [node.id, parent]
            ))
        }
        return out
    }

    private static func alsoUnder(_ node: Node, _ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        var seen = Set<NodeID>()
        for secondary in node.alsoUnder {
            if !seen.insert(secondary).inserted {
                out.append(Diagnostic(
                    rule: .duplicateAlsoUnder,
                    message: "`also_under` lists `\(secondary)` more than once",
                    nodes: [node.id, secondary]
                ))
                continue
            }
            if secondary == node.id {
                out.append(Diagnostic(
                    rule: .selfContains,
                    message: "`also_under` lists the node itself",
                    nodes: [node.id]
                ))
                continue
            }
            if secondary == node.parent {
                out.append(Diagnostic(
                    rule: .alsoUnderRepeatsPrimaryParent,
                    message: "`also_under` repeats the primary parent `\(secondary)`; "
                        + "secondary parents are additional cross-listings",
                    nodes: [node.id, secondary]
                ))
                continue
            }
            guard let target = graph[secondary] else {
                out.append(Diagnostic(
                    rule: .danglingAlsoUnder,
                    message: "`also_under` references unknown node `\(secondary)`",
                    nodes: [node.id, secondary]
                ))
                continue
            }
            if !target.kind.isStructural {
                out.append(Diagnostic(
                    rule: .alsoUnderNotStructural,
                    message: "`contains` parents are structural; `\(secondary)` is a "
                        + "`\(target.kind.rawValue)`",
                    nodes: [node.id, secondary]
                ))
            }
        }
        return out
    }

    private static func requires(_ node: Node, _ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        var seen = Set<NodeID>()
        for prerequisite in node.requires {
            if !seen.insert(prerequisite).inserted {
                out.append(Diagnostic(
                    rule: .duplicateRequires,
                    message: "`requires` lists `\(prerequisite)` more than once",
                    nodes: [node.id, prerequisite]
                ))
                continue
            }
            if graph[prerequisite] == nil {
                out.append(Diagnostic(
                    rule: .danglingRequires,
                    message: "`requires` references unknown node `\(prerequisite)`",
                    nodes: [node.id, prerequisite]
                ))
            }
        }
        return out
    }

    private static func relates(_ node: Node, _ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for ref in node.relates {
            if ref.id == node.id {
                out.append(Diagnostic(
                    rule: .selfRelates,
                    message: "`relates` points at the node itself",
                    nodes: [node.id]
                ))
                continue
            }
            // The connection is itself knowledge (§2.3), so an unexplained edge is
            // an empty node, not a terse one.
            if ref.note.allSatisfy(\.isWhitespace) {
                out.append(Diagnostic(
                    rule: .emptyRelatesNote,
                    message: "`relates` edge to `\(ref.id)` has no note explaining the connection",
                    nodes: [node.id, ref.id]
                ))
            }
            if graph[ref.id] == nil {
                out.append(Diagnostic(
                    rule: .danglingRelates,
                    message: "`relates` references unknown node `\(ref.id)`",
                    nodes: [node.id, ref.id]
                ))
            }
        }
        return out
    }

    private static func structuralPurity(_ node: Node) -> [Diagnostic] {
        guard node.kind.isStructural else { return [] }
        var out: [Diagnostic] = []
        if node.statement != nil {
            out.append(Diagnostic(
                rule: .structuralNodeHasStatement,
                message: "structural nodes hold no `statement` — they are navigation, not knowledge",
                nodes: [node.id]
            ))
        }
        if !node.requires.isEmpty {
            out.append(Diagnostic(
                rule: .structuralNodeHasRequires,
                message: "structural nodes are not learnable and carry no `requires`",
                nodes: [node.id]
            ))
        }
        if !node.relates.isEmpty {
            out.append(Diagnostic(
                rule: .structuralNodeHasRelates,
                message: "structural nodes are not learnable and carry no `relates`",
                nodes: [node.id]
            ))
        }
        return out
    }

    // MARK: Whole-graph checks

    /// The prefix rule already makes a primary-parent cycle impossible, but the walk
    /// is O(n) and a validator that assumes its own other rules passed is a liar.
    private static func containsCycles(_ graph: KnowledgeGraph) -> [Diagnostic] {
        var settled = Set<NodeID>()
        var out: [Diagnostic] = []
        var reported = Set<String>()
        for node in graph.nodes {
            var path: [NodeID] = []
            var current: NodeID? = node.id
            while let id = current, !settled.contains(id) {
                if let start = path.firstIndex(of: id) {
                    let cycle = canonicalCycle(Array(path[start...]))
                    if reported.insert(closedPath(cycle)).inserted {
                        out.append(Diagnostic(
                            rule: .containsCycle,
                            message: "`contains` cycle among primary parents: \(closedPath(cycle))",
                            nodes: cycle,
                            path: cycle + [cycle[0]]
                        ))
                    }
                    break
                }
                path.append(id)
                current = graph[id]?.parent
                if let next = current, graph[next] == nil { current = nil }
            }
            settled.formUnion(path)
        }
        return out
    }

    /// Iterative three-colour DFS — the corpus is deep enough (10k-node chains are a
    /// stated stress case) that recursion would overflow the stack.
    private static func requiresCycles(_ graph: KnowledgeGraph) -> [[NodeID]] {
        var colour: [NodeID: Int] = [:]  // 1 = on the current path, 2 = finished
        var cycles: [[NodeID]] = []
        var reported = Set<String>()

        for node in graph.nodes where colour[node.id] == nil {
            var frames: [(id: NodeID, next: Int)] = [(node.id, 0)]
            var path: [NodeID] = [node.id]
            colour[node.id] = 1
            while let frame = frames.last {
                let neighbours = graph.prerequisites(of: frame.id)
                guard frame.next < neighbours.count else {
                    colour[frame.id] = 2
                    path.removeLast()
                    frames.removeLast()
                    continue
                }
                frames[frames.count - 1].next += 1
                let neighbour = neighbours[frame.next]
                if colour[neighbour] == 1 {
                    if let start = path.firstIndex(of: neighbour) {
                        let cycle = canonicalCycle(Array(path[start...]))
                        if reported.insert(closedPath(cycle)).inserted { cycles.append(cycle) }
                    }
                } else if colour[neighbour] == nil {
                    colour[neighbour] = 1
                    path.append(neighbour)
                    frames.append((neighbour, 0))
                }
            }
        }
        return cycles.sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// §2.3: only direct prerequisites are authored. Edge X→Pᵢ is redundant exactly
    /// when some *other* prerequisite Pⱼ of X already reaches Pᵢ.
    ///
    /// The union of all Pⱼ's ancestor sets is computed in one shared-visited sweep per
    /// node, and nodes with a single prerequisite are skipped outright (nothing to be
    /// redundant against) — which is what keeps this linear on long chains instead of
    /// quadratic.
    private static func redundantRequires(_ graph: KnowledgeGraph) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for node in graph.nodes {
            let prerequisites = graph.prerequisites(of: node.id)
            guard prerequisites.count > 1 else { continue }

            var reached = Set<NodeID>()
            var cameFrom: [NodeID: NodeID] = [:]
            var rootedAt: [NodeID: NodeID] = [:]
            for seed in prerequisites where !reached.contains(seed) {
                var queue: [NodeID] = []
                var head = 0
                for next in graph.prerequisites(of: seed) where reached.insert(next).inserted {
                    cameFrom[next] = seed
                    rootedAt[next] = seed
                    queue.append(next)
                }
                while head < queue.count {
                    let current = queue[head]
                    head += 1
                    for next in graph.prerequisites(of: current) where reached.insert(next).inserted {
                        cameFrom[next] = current
                        rootedAt[next] = rootedAt[current]
                        queue.append(next)
                    }
                }
            }

            for redundant in prerequisites where reached.contains(redundant) {
                var chain = [redundant]
                var current = redundant
                while current != rootedAt[redundant], let up = cameFrom[current] {
                    chain.append(up)
                    current = up
                }
                chain.reverse()
                out.append(Diagnostic(
                    rule: .redundantRequires,
                    message: "`requires \(redundant)` is implied transitively via "
                        + chain.map(\.rawValue).joined(separator: " → ")
                        + "; author only the transitive reduction",
                    nodes: [node.id, redundant],
                    path: [node.id] + chain
                ))
            }
        }
        return out
    }

    /// One `relates` connection, authored twice (from both endpoints, or twice on one),
    /// is one `edge_states` key with two owners (§3.2).
    private static func duplicateRelates(_ graph: KnowledgeGraph) -> [Diagnostic] {
        var occurrences: [String: (edge: RelatesEdge, count: Int)] = [:]
        for node in graph.nodes {
            for ref in node.relates {
                let edge = RelatesEdge(node.id, ref.id, note: ref.note)
                let existing = occurrences[edge.key]
                occurrences[edge.key] = (existing?.edge ?? edge, (existing?.count ?? 0) + 1)
            }
        }
        return occurrences.values.filter { $0.count > 1 }
            .map(\.edge)
            .sorted()
            .map { edge in
                Diagnostic(
                    rule: .duplicateRelates,
                    message: "the connection `\(edge.key)` is authored more than once; "
                        + "`relates` is undirected, so declare it on one endpoint",
                    nodes: [edge.a, edge.b]
                )
            }
    }

    // MARK: Helpers

    /// Rotate so the lexicographically smallest id leads — same cycle, same reported
    /// order, whatever node the DFS happened to enter from.
    private static func canonicalCycle(_ cycle: [NodeID]) -> [NodeID] {
        guard let pivot = cycle.indices.min(by: { cycle[$0] < cycle[$1] }) else { return cycle }
        return Array(cycle[pivot...] + cycle[..<pivot])
    }

    private static func closedPath(_ cycle: [NodeID]) -> String {
        (cycle + [cycle[0]]).map(\.rawValue).joined(separator: " → ")
    }
}
