/// A node reached by a traversal, with its BFS distance from the start node.
/// Depth is the *shortest* number of edges, which is what §4.3's γᵈ damping wants.
public struct ReachedNode: Hashable, Sendable, Comparable {
    public let id: NodeID
    public let depth: Int

    public init(id: NodeID, depth: Int) {
        self.id = id
        self.depth = depth
    }

    public static func < (lhs: ReachedNode, rhs: ReachedNode) -> Bool {
        (lhs.id, lhs.depth) < (rhs.id, rhs.depth)
    }
}

/// The content graph plus the derived indexes that are cheap to keep eagerly.
///
/// Deliberately *not* precomputed: transitive `requires` ancestor/descendant sets.
/// At the target corpus size (§7: 5k–15k nodes) with the deep chains this model
/// encourages, materializing them is O(n²) — they are computed per query instead,
/// in time proportional to the answer.
///
/// Every index holds only *resolvable* references; dangling ones are silently
/// absent here and reported by `GraphValidator`, so a broken graph still loads.
public struct KnowledgeGraph: Sendable {
    /// All nodes, ordered by id (ties broken by authoring order) so anything derived
    /// by iteration is deterministic.
    public let nodes: [Node]
    public let nodesByID: [NodeID: Node]

    /// Children by *primary* `contains` parent — the taxonomy tree.
    public let childrenByParent: [NodeID: [NodeID]]
    /// Children by any `contains` parent, primary or `also_under` — the taxonomy DAG (§2.3).
    public let containedChildrenByParent: [NodeID: [NodeID]]
    /// Reverse of `requires`: who lists this node as a direct prerequisite.
    public let dependentsByPrerequisite: [NodeID: [NodeID]]
    /// Forward `requires`, normalized (deduped, sorted, resolvable only).
    public let prerequisitesByNode: [NodeID: [NodeID]]
    /// `relates` adjacency with both endpoints listed — each authored relation
    /// appears on the node that authored it *and* on its target.
    public let relatedByNode: [NodeID: [RelatesRef]]
    /// Every authored relation in canonical undirected form, sorted.
    public let relatesEdges: [RelatesEdge]

    public init(nodes input: [Node]) {
        // Sort by (id, authoring position): a total order even when ids collide,
        // so a duplicate-id graph still loads the same way every time.
        nodes = input.enumerated()
            .sorted { ($0.element.id, $0.offset) < ($1.element.id, $1.offset) }
            .map(\.element)

        var byID: [NodeID: Node] = [:]
        byID.reserveCapacity(nodes.count)
        for node in nodes where byID[node.id] == nil { byID[node.id] = node }
        nodesByID = byID

        var children: [NodeID: [NodeID]] = [:]
        var contained: [NodeID: [NodeID]] = [:]
        var dependents: [NodeID: [NodeID]] = [:]
        var prerequisites: [NodeID: [NodeID]] = [:]
        var related: [NodeID: [RelatesRef]] = [:]
        var edges: [RelatesEdge] = []

        for node in nodes {
            if let parent = node.parent, byID[parent] != nil {
                children[parent, default: []].append(node.id)
                contained[parent, default: []].append(node.id)
            }
            for secondary in node.alsoUnder where byID[secondary] != nil {
                contained[secondary, default: []].append(node.id)
            }
            let reachable = node.requires.filter { byID[$0] != nil }
            if !reachable.isEmpty {
                prerequisites[node.id] = Self.normalized(reachable)
                for prerequisite in reachable {
                    dependents[prerequisite, default: []].append(node.id)
                }
            }
            for ref in node.relates where byID[ref.id] != nil {
                related[node.id, default: []].append(ref)
                related[ref.id, default: []].append(RelatesRef(id: node.id, note: ref.note))
                edges.append(RelatesEdge(node.id, ref.id, note: ref.note))
            }
        }

        childrenByParent = children.mapValues(Self.normalized)
        containedChildrenByParent = contained.mapValues(Self.normalized)
        dependentsByPrerequisite = dependents.mapValues(Self.normalized)
        prerequisitesByNode = prerequisites
        relatedByNode = related.mapValues { Array(Set($0)).sorted() }
        relatesEdges = Array(Set(edges)).sorted()
    }

    private static func normalized(_ ids: [NodeID]) -> [NodeID] {
        var seen = Set<NodeID>()
        return ids.sorted().filter { seen.insert($0).inserted }
    }

    // MARK: Lookups

    public subscript(id: NodeID) -> Node? { nodesByID[id] }

    public func contains(_ id: NodeID) -> Bool { nodesByID[id] != nil }

    public var branches: [NodeID] {
        nodes.filter { $0.kind == .branch }.map(\.id)
    }

    public func children(of id: NodeID) -> [NodeID] { childrenByParent[id] ?? [] }

    public func containedChildren(of id: NodeID) -> [NodeID] { containedChildrenByParent[id] ?? [] }

    /// Every learnable node inside a subject, at any taxonomy depth — the membership
    /// question §6.5 asks of a branch or subbranch.
    ///
    /// Descends the `contains` **DAG** (`containedChildren`), not the primary tree:
    /// §2.3 says a secondary parent is there precisely because the topic belongs to
    /// that subject too, and generating functions being cross-listed under
    /// Probability is a claim that you cannot say you know Probability without them.
    /// A node reachable both ways appears once.
    ///
    /// Structural nodes are dropped rather than returned alongside their contents:
    /// they carry no score (§2.1), so one in a target set would sit unmet forever.
    public func contentDescendants(of id: NodeID) -> [NodeID] {
        guard nodesByID[id] != nil else { return [] }
        var visited: Set<NodeID> = [id]
        var stack: [NodeID] = [id]
        var found: [NodeID] = []
        while let next = stack.popLast() {
            for child in containedChildren(of: next) where visited.insert(child).inserted {
                if nodesByID[child]?.kind.isContent == true { found.append(child) }
                stack.append(child)
            }
        }
        return found.sorted()
    }

    public func prerequisites(of id: NodeID) -> [NodeID] { prerequisitesByNode[id] ?? [] }

    public func dependents(of id: NodeID) -> [NodeID] { dependentsByPrerequisite[id] ?? [] }

    public func related(to id: NodeID) -> [RelatesRef] { relatedByNode[id] ?? [] }

    // MARK: Transitive `requires` queries

    /// Every transitive prerequisite of `id`, sorted. Work is proportional to the
    /// answer, not to the graph. `maxDepth` caps the hop distance (§4.3's `D_max`).
    public func requiresAncestors(of id: NodeID, maxDepth: Int? = nil) -> [NodeID] {
        requiresAncestorsByDepth(of: id, maxDepth: maxDepth).map(\.id)
    }

    /// Every transitive prerequisite of *any* node in `ids`, sorted, excluding the
    /// start set itself. One traversal rather than one per start, so a subject-sized
    /// goal set (§6.5) costs what its reachable region costs, not what it costs
    /// times the number of targets — the same regions overlap almost entirely.
    public func requiresAncestors(ofAll ids: some Sequence<NodeID>) -> [NodeID] {
        reach(from: ids, maxDepth: nil, neighbors: prerequisitesByNode).map(\.id)
    }

    /// Every node that transitively requires `id`, sorted.
    public func requiresDescendants(of id: NodeID, maxDepth: Int? = nil) -> [NodeID] {
        requiresDescendantsByDepth(of: id, maxDepth: maxDepth).map(\.id)
    }

    public func requiresAncestorsByDepth(of id: NodeID, maxDepth: Int? = nil) -> [ReachedNode] {
        reach(from: CollectionOfOne(id), maxDepth: maxDepth, neighbors: prerequisitesByNode)
    }

    public func requiresDescendantsByDepth(of id: NodeID, maxDepth: Int? = nil) -> [ReachedNode] {
        reach(from: CollectionOfOne(id), maxDepth: maxDepth, neighbors: dependentsByPrerequisite)
    }

    /// Breadth-first so `depth` is the shortest distance, and visit-marked so a
    /// diamond is deduped and an (invalid) cycle still terminates. With several
    /// starts, `depth` is the shortest distance from the *nearest* of them.
    private func reach(
        from starts: some Sequence<NodeID>,
        maxDepth: Int?,
        neighbors: [NodeID: [NodeID]]
    ) -> [ReachedNode] {
        let resolved = starts.filter { nodesByID[$0] != nil }
        guard !resolved.isEmpty else { return [] }
        var visited: Set<NodeID> = Set(resolved)
        var frontier: [NodeID] = resolved
        var found: [ReachedNode] = []
        var depth = 0
        while !frontier.isEmpty {
            depth += 1
            if let maxDepth, depth > maxDepth { break }
            var next: [NodeID] = []
            for node in frontier {
                for neighbor in neighbors[node] ?? [] where visited.insert(neighbor).inserted {
                    found.append(ReachedNode(id: neighbor, depth: depth))
                    next.append(neighbor)
                }
            }
            frontier = next
        }
        found.sort()
        return found
    }
}
