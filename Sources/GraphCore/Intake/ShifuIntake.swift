import Foundation

/// §8.2's boundary, as a parser.
///
/// Shifu is "a data contract, not a code dependency": it owns observation and
/// inference-to-node mapping, this project owns the graph, scoring and display,
/// and the only thing that crosses is a document of evidence events. So the
/// contract is a *wire format* with a version on it, and this file is the whole of
/// what the project promises to accept.
///
/// Three properties are deliberate and are the reason the wire type is not simply
/// `[EvidenceEvent]`:
///
/// 1. **The transport determines the source; the payload cannot claim one.** There
///    is no `source` field. Everything that arrives through this door is stamped
///    `source: shifu`, so a document dropped into the intake directory can never
///    forge itself into a `test`. A `source` key in the payload is reported as
///    ignored rather than honoured.
/// 2. **Shifu observes; it does not assess.** There is no `grade` either — §8.2's
///    contract is `{node ids, confidence, source, timestamp}`, and confidence is
///    the *only* strength dial. The intake stamps a neutral `good`, exactly as
///    placement does for inferred knowledge (D8.4): inference says *whether* the
///    user knows something, never how fluently.
/// 3. **An event is atomic.** If any id in an event is unknown, the whole event is
///    rejected rather than partially honoured — an observation naming three nodes
///    is one claim about a moment of usage, and silently keeping two of them
///    changes what it says.
public enum ShifuIntake {
    /// The wire-format version. Frozen: a change to what the fields *mean* takes a
    /// new number, and a document carrying an unknown number is rejected whole
    /// rather than interpreted under a guess.
    public static let schema = 1

    /// What one document produced.
    public struct Report: Sendable {
        /// Ready to append to the evidence log, in document order.
        public var events: [EvidenceEvent]
        public var diagnostics: [IntakeDiagnostic]
        /// Observations accepted (one observation can name several targets, so this
        /// is ≤ `events.count`).
        public var accepted: Int
        /// Observations rejected for a reason the diagnostics name.
        public var rejected: Int
        /// The document itself was unusable — malformed JSON, wrong shape, or an
        /// unsupported schema version. No observation in it was even looked at.
        public var isMalformed: Bool

        public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

        static func malformed(_ diagnostic: IntakeDiagnostic) -> Report {
            Report(
                events: [], diagnostics: [diagnostic], accepted: 0, rejected: 0, isMalformed: true)
        }
    }

    /// Parse one document against the graph it references.
    ///
    /// Total: never throws, never traps, and never returns events it could not
    /// check. Hand-rolled over `JSONSerialization` rather than `Codable` because
    /// the exit criterion is about *diagnostics* — "malformed and unknown-id events
    /// are rejected with diagnostics, never crash, never corrupt the log" — and a
    /// `DecodingError` for a typo in the fourth event of a document says far less
    /// than "event 4: `confidence` must be a number in (0, 1], got \"high\"".
    public static func parse(_ data: Data, graph: KnowledgeGraph) -> Report {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            return .malformed(.init(reason: .notJSON("\(error.localizedDescription)")))
        }
        guard let object = root as? [String: Any] else {
            return .malformed(.init(reason: .envelopeNotAnObject))
        }

        guard let version = object["schema"] else {
            return .malformed(.init(reason: .missingField("schema")))
        }
        guard let version = version as? Int else {
            return .malformed(.init(reason: .wrongType(field: "schema", expected: "an integer")))
        }
        guard version == schema else {
            return .malformed(
                .init(reason: .unsupportedSchema(found: version, supported: schema)))
        }

        guard let rawEvents = object["events"] else {
            return .malformed(.init(reason: .missingField("events")))
        }
        guard let rawEvents = rawEvents as? [Any] else {
            return .malformed(.init(reason: .wrongType(field: "events", expected: "an array")))
        }

        var diagnostics: [IntakeDiagnostic] = []
        for key in object.keys.sorted() where !envelopeKeys.contains(key) {
            diagnostics.append(.init(reason: .ignoredField(key), severity: .warning))
        }

        var events: [EvidenceEvent] = []
        var accepted = 0
        var rejected = 0

        for (index, raw) in rawEvents.enumerated() {
            switch observation(raw, at: index, graph: graph) {
            case let .success(produced, notes):
                events += produced
                diagnostics += notes
                accepted += 1
            case let .failure(notes):
                diagnostics += notes
                rejected += 1
            }
        }

        return Report(
            events: events, diagnostics: diagnostics, accepted: accepted, rejected: rejected,
            isMalformed: false)
    }

    // MARK: - One observation

    private static let envelopeKeys: Set<String> = ["schema", "producer", "events"]
    private static let observationKeys: Set<String> = [
        "at", "nodes", "edges", "confidence", "activity",
    ]

    private enum Outcome {
        case success([EvidenceEvent], [IntakeDiagnostic])
        case failure([IntakeDiagnostic])
    }

    private static func observation(_ raw: Any, at index: Int, graph: KnowledgeGraph) -> Outcome {
        func fail(_ reason: IntakeDiagnostic.Reason) -> Outcome {
            .failure([.init(event: index, reason: reason)])
        }

        guard let object = raw as? [String: Any] else {
            return fail(.eventNotAnObject)
        }

        var notes: [IntakeDiagnostic] = []
        for key in object.keys.sorted() where !observationKeys.contains(key) {
            notes.append(.init(event: index, reason: .ignoredField(key), severity: .warning))
        }

        guard let rawAt = object["at"] else { return fail(.missingField("at")) }
        guard let text = rawAt as? String else {
            return fail(.wrongType(field: "at", expected: "an ISO-8601 timestamp string"))
        }
        guard let at = ISO8601Timestamp.date(from: text) else {
            return fail(.badTimestamp(text))
        }

        guard let rawConfidence = object["confidence"] else {
            return fail(.missingField("confidence"))
        }
        // `is Bool` is the wrong test: `JSONSerialization` hands back `NSNumber`,
        // and *every* `NSNumber` holding 0 or 1 casts to `Bool` — so the obvious
        // guard rejects `"confidence": 0` as "not a number" and, worse, would have
        // to be written the other way round to let it through, at which point
        // `true` sails in as 1.0, the strongest claim the contract can make, from
        // a field that was not a number at all. The type id is the only thing that
        // actually distinguishes them.
        guard let number = rawConfidence as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return fail(.wrongType(field: "confidence", expected: "a number in (0, 1]"))
        }
        let confidence = number.doubleValue
        guard confidence > 0, confidence <= 1 else {
            return fail(.confidenceOutOfRange(confidence))
        }

        var activity: String?
        if let rawActivity = object["activity"] {
            guard let text = rawActivity as? String else {
                return fail(.wrongType(field: "activity", expected: "a string"))
            }
            activity = text.isEmpty ? nil : text
        }

        var targets: [EvidenceTarget] = []

        if let rawNodes = object["nodes"] {
            guard let list = rawNodes as? [Any] else {
                return fail(.wrongType(field: "nodes", expected: "an array of node ids"))
            }
            for element in list {
                guard let text = element as? String else {
                    return fail(.wrongType(field: "nodes", expected: "an array of node ids"))
                }
                let id = NodeID(text)
                guard let node = graph[id] else { return fail(.unknownNode(text)) }
                guard node.kind.isContent else { return fail(.structuralTarget(text)) }
                targets.append(.node(id))
            }
        }

        if let rawEdges = object["edges"] {
            guard let list = rawEdges as? [Any] else {
                return fail(.wrongType(field: "edges", expected: "an array of \"a ~ b\" keys"))
            }
            for element in list {
                guard let key = element as? String else {
                    return fail(.wrongType(field: "edges", expected: "an array of \"a ~ b\" keys"))
                }
                guard graph.relatesEdges.contains(where: { $0.key == key }) else {
                    return fail(.unknownEdge(key))
                }
                targets.append(.edge(key))
            }
        }

        guard !targets.isEmpty else { return fail(.noTargets) }

        // Duplicate targets inside one observation would apply the same boost
        // twice — the same compounding D8.2 found in multi-target grading.
        var seen: Set<String> = []
        let events = targets.filter { seen.insert($0.key).inserted }.map { target in
            EvidenceEvent(
                at: at,
                target: target,
                // Neutral by construction, and it is what makes the node count as
                // *learned* (§4.5): observed usage is evidence of retrieval, and
                // `confidence` is what says how weakly.
                grade: .good,
                confidence: confidence,
                source: .shifu,
                note: activity)
        }
        return .success(events, notes)
    }
}

/// Something the intake could not use, or used but wants on the record.
///
/// Diagnostics are the deliverable here, not a side effect: Shifu is a separate
/// program built by someone else, and the only way its author can tell a rejected
/// document from an accepted one is what this prints.
public struct IntakeDiagnostic: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: Hashable, Sendable {
        /// The document or the observation was not used.
        case error
        /// It was used, but something in it was ignored.
        case warning
    }

    public enum Reason: Hashable, Sendable {
        case notJSON(String)
        case envelopeNotAnObject
        case eventNotAnObject
        case missingField(String)
        case wrongType(field: String, expected: String)
        case unsupportedSchema(found: Int, supported: Int)
        case badTimestamp(String)
        case confidenceOutOfRange(Double)
        case noTargets
        case unknownNode(String)
        case unknownEdge(String)
        case structuralTarget(String)
        case ignoredField(String)
    }

    /// Index into the document's `events`, or `nil` for a document-level problem.
    public var event: Int?
    public var reason: Reason
    public var severity: Severity

    public init(event: Int? = nil, reason: Reason, severity: Severity = .error) {
        self.event = event
        self.reason = reason
        self.severity = severity
    }

    public var description: String {
        let scope = event.map { "event \($0)" } ?? "document"
        return "\(scope): \(message)"
    }

    public var message: String {
        switch reason {
        case let .notJSON(detail):
            return "not JSON — \(detail)"
        case .envelopeNotAnObject:
            return "top level must be an object with `schema` and `events`"
        case .eventNotAnObject:
            return "must be an object"
        case let .missingField(name):
            return "missing required field `\(name)`"
        case let .wrongType(field, expected):
            return "`\(field)` must be \(expected)"
        case let .unsupportedSchema(found, supported):
            return
                "schema \(found) is not supported by this build (it speaks \(supported)) — "
                + "rejected whole rather than interpreted under a guess"
        case let .badTimestamp(text):
            return "`at` is not an ISO-8601 UTC timestamp: \(text)"
        case let .confidenceOutOfRange(value):
            return "`confidence` must lie in (0, 1], got \(value)"
        case .noTargets:
            return "names no target — `nodes` and/or `edges` must contain at least one id"
        case let .unknownNode(id):
            return "no such node in this corpus: \(id)"
        case let .unknownEdge(key):
            return "no such `relates` edge in this corpus: \(key)"
        case let .structuralTarget(id):
            return
                "\(id) is a branch or subbranch — evidence attaches to content nodes, "
                + "and a hub's colour is not a thing the user knows"
        case let .ignoredField(name):
            return
                "`\(name)` is not part of the v\(ShifuIntake.schema) contract and was ignored"
                + (name == "source" || name == "grade"
                    ? " — the transport stamps the source, and Shifu observes rather than grades"
                    : "")
        }
    }
}
