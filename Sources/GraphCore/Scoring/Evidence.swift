import Foundation

/// §5.1: everything the system knows about the user arrives as evidence events,
/// and scores are a fold over the log. The log is append-only and is the ground
/// truth (§3.2) — FSRS state is a cache recomputable from it, which is what lets
/// the algorithm be upgraded and replayed later.
public enum EvidenceSource: String, Codable, Hashable, Sendable, CaseIterable {
    case test
    case selfReport = "self-report"
    case implicit
    case shifu

    /// Ordering rank within one instant. Direct evidence must be applied before a
    /// derived boost: the measurement anchors the state and the damped implicit
    /// review lands on top of it (where `max` often makes it a no-op). Applying
    /// the boost first would let an explicit review compound an inflated
    /// stability. Sorting on `rawValue` would put "implicit" before "test".
    ///
    /// `shifu` ranks with `implicit` for the same reason and not by analogy: an
    /// observation is inferred evidence (§5.1's inferred tier), so if the user was
    /// *measured* on a node in the same instant that Shifu guessed at it, the
    /// measurement is the one that sets the state.
    var foldRank: Int { isInferred ? 1 : 0 }

    /// Whether evidence from this source is inferred rather than measured. Drives
    /// fold ordering; the fold's *weighting* keys off `confidence` instead, so that
    /// a source is never quietly given a second decay model (D8.4).
    var isInferred: Bool { self == .implicit || self == .shifu }
}

/// Evidence attaches to a node or to a `relates` edge (§4.4 — the connection
/// between two topics is knowledge over and above the endpoints).
public enum EvidenceTarget: Codable, Hashable, Sendable, Comparable {
    case node(NodeID)
    /// Canonical `"a ~ b"` key, matching §3.2's `edge_states` form.
    case edge(String)

    public var key: String {
        switch self {
        case let .node(id): return id.rawValue
        case let .edge(key): return key
        }
    }

    public var nodeID: NodeID? {
        if case let .node(id) = self { return id }
        return nil
    }

    enum CodingKeys: String, CodingKey { case node, edge }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(NodeID.self, forKey: .node) {
            self = .node(id)
        } else if let key = try container.decodeIfPresent(String.self, forKey: .edge) {
            self = .edge(key)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "target has no node or edge"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .node(id): try container.encode(id, forKey: .node)
        case let .edge(key): try container.encode(key, forKey: .edge)
        }
    }

    public static func < (lhs: EvidenceTarget, rhs: EvidenceTarget) -> Bool {
        lhs.key < rhs.key
    }
}

public struct EvidenceEvent: Codable, Hashable, Sendable {
    public var at: Date
    public var target: EvidenceTarget
    /// A graded review. §5.1 allows `grade` *or* `confidence`; the fold consumes
    /// grades — confidence-weighted inferred evidence is Phase 8/§5.3 work.
    public var grade: Grade?
    /// Confidence in [0, 1] for inferred (untested) evidence.
    public var confidence: Double?
    public var source: EvidenceSource
    /// The problem that produced this evidence, when there was one (§5.2).
    public var problem: String?
    /// Implicit events only: the explicitly reviewed node this propagated from.
    public var origin: NodeID?
    /// Implicit events only: `requires`-hop distance from `origin` (§4.3).
    public var depth: Int?
    /// Implicit events only: the damping weight γᵈ actually applied.
    public var weight: Double?
    /// Free text describing where the evidence came from, when the producer knows
    /// something the other fields cannot hold. Written by §8.2's intake from an
    /// observation's `activity`; never read by the fold.
    ///
    /// Additive to log format 1 on purpose: `Codable` omits a nil optional, so
    /// existing logs are byte-identical and an older build ignores the key.
    public var note: String?

    public init(
        at: Date,
        target: EvidenceTarget,
        grade: Grade? = nil,
        confidence: Double? = nil,
        source: EvidenceSource,
        problem: String? = nil,
        origin: NodeID? = nil,
        depth: Int? = nil,
        weight: Double? = nil,
        note: String? = nil
    ) {
        self.at = at
        self.target = target
        self.grade = grade
        self.confidence = confidence
        self.source = source
        self.problem = problem
        self.origin = origin
        self.depth = depth
        self.weight = weight
        self.note = note
    }

    /// Total order for the fold. FSRS updates do not commute, so same-timestamp
    /// events must be ordered by content rather than by arrival — that is what
    /// makes replay reproducible (§3.2).
    static func foldOrder(_ lhs: EvidenceEvent, _ rhs: EvidenceEvent) -> Bool {
        if lhs.at != rhs.at { return lhs.at < rhs.at }
        if lhs.target != rhs.target { return lhs.target < rhs.target }
        // Explicit before implicit, so a node reviewed directly and boosted in the
        // same instant sees the direct review first.
        if lhs.source.foldRank != rhs.source.foldRank {
            return lhs.source.foldRank < rhs.source.foldRank
        }
        if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
        if lhs.grade != rhs.grade {
            return (lhs.grade?.rawValue ?? -1) < (rhs.grade?.rawValue ?? -1)
        }
        if lhs.depth != rhs.depth { return (lhs.depth ?? -1) < (rhs.depth ?? -1) }
        if lhs.origin != rhs.origin {
            return (lhs.origin?.rawValue ?? "") < (rhs.origin?.rawValue ?? "")
        }
        if lhs.problem != rhs.problem { return (lhs.problem ?? "") < (rhs.problem ?? "") }
        // Two observations of the same node at the same instant differing only in
        // what Shifu was watching still have to fold in a fixed order.
        return (lhs.note ?? "") < (rhs.note ?? "")
    }
}

/// First line of the log. §4.2 requires the algorithm version to be recorded so a
/// log written under one model can be identified and replayed under another.
public struct EvidenceLogHeader: Codable, Hashable, Sendable {
    public var logFormat: Int
    public var algorithm: String
    public var oracle: String
    public var parameters: [Double]

    public init(
        logFormat: Int = EvidenceLog.format,
        algorithm: String = FSRSVersion.algorithm,
        oracle: String = FSRSVersion.oracle,
        parameters: [Double] = FSRSParameters.fsrs6DefaultWeights
    ) {
        self.logFormat = logFormat
        self.algorithm = algorithm
        self.oracle = oracle
        self.parameters = parameters
    }
}

/// A line the reader could not use. Corruption is reported, never fatal: a
/// half-written line from a crash must not cost the user their whole history.
public struct EvidenceDefect: Hashable, Sendable, CustomStringConvertible {
    public enum Reason: Hashable, Sendable {
        case notJSON(String)
        case missingHeader
        case unknownFormat(Int)
    }

    public var line: Int
    public var reason: Reason
    public var raw: String

    public var description: String {
        switch reason {
        case let .notJSON(message): return "line \(line): \(message)"
        case .missingHeader: return "line \(line): expected a log header first"
        case let .unknownFormat(version): return "line \(line): unknown log format v\(version)"
        }
    }
}

public struct EvidenceLogContents: Sendable {
    public var header: EvidenceLogHeader?
    public var events: [EvidenceEvent]
    public var defects: [EvidenceDefect]
}

/// Append-only JSONL evidence log (§3.2). Deliberately not a database — the plan
/// defers persistence, and this is replayable and greppable in the meantime.
public struct EvidenceLog: Sendable {
    public static let format = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/MathTree/evidence.jsonl`. Other trees pass
    /// their own `fileName` — one directory, one log per tree.
    public static func defaultURL(
        applicationSupport: URL? = nil, bundleName: String = "MathTree",
        fileName: String = "evidence.jsonl"
    ) throws -> URL {
        let base =
            try applicationSupport
            ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
        return base.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return decoder
    }

    /// Reads the whole log, skipping and reporting anything unusable.
    public func read() throws -> EvidenceLogContents {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return EvidenceLogContents(header: nil, events: [], defects: [])
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return Self.parse(text)
    }

    static func parse(_ text: String) -> EvidenceLogContents {
        let decoder = decoder()
        var header: EvidenceLogHeader?
        var events: [EvidenceEvent] = []
        var defects: [EvidenceDefect] = []

        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
        {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let number = offset + 1
            let data = Data(line.utf8)

            if header == nil {
                do {
                    let candidate = try decoder.decode(EvidenceLogHeader.self, from: data)
                    guard candidate.logFormat == format else {
                        defects.append(
                            .init(
                                line: number, reason: .unknownFormat(candidate.logFormat), raw: line))
                        continue
                    }
                    header = candidate
                    continue
                } catch {
                    // Not a header — fall through and try it as an event, so a log
                    // whose header was lost still yields its history.
                    defects.append(.init(line: number, reason: .missingHeader, raw: line))
                }
            }

            do {
                events.append(try decoder.decode(EvidenceEvent.self, from: data))
            } catch {
                defects.append(.init(line: number, reason: .notJSON("\(error)"), raw: line))
            }
        }

        return EvidenceLogContents(header: header, events: events, defects: defects)
    }

    /// Appends events, writing the header first if the log is new.
    @discardableResult
    public func append(_ events: [EvidenceEvent], header: EvidenceLogHeader = .init()) throws -> Int
    {
        guard !events.isEmpty else { return 0 }
        let encoder = Self.encoder()
        var payload = Data()

        let manager = FileManager.default
        let exists = manager.fileExists(atPath: url.path)
        if !exists {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            payload.append(try encoder.encode(header))
            payload.append(0x0A)
        }
        for event in events {
            payload.append(try encoder.encode(event))
            payload.append(0x0A)
        }

        if exists {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url, options: .atomic)
        }
        return events.count
    }
}

extension JSONEncoder.DateEncodingStrategy {
    /// Round-trips exactly with the decoding counterpart, so a replayed log is
    /// byte-identical to the original.
    static var iso8601WithFractionalSeconds: Self {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Timestamp.string(from: date))
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: Self {
        .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601Timestamp.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "not an ISO-8601 UTC timestamp: \(text)"))
            }
            return date
        }
    }
}

/// `ISO8601DateFormatter` is a reference type and not `Sendable`, so it cannot be
/// shared under strict concurrency. `Date.ISO8601FormatStyle` is a value type and
/// is, which keeps this allocation-free per line.
enum ISO8601Timestamp {
    private static let withFraction = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true, timeZone: .gmt)
    private static let withoutFraction = Date.ISO8601FormatStyle(
        includingFractionalSeconds: false, timeZone: .gmt)

    static func string(from date: Date) -> String {
        withFraction.format(date)
    }

    /// Accepts both forms — hand-authored fixtures and §3.2's own examples omit
    /// the fractional part.
    static func date(from text: String) -> Date? {
        (try? withFraction.parse(text)) ?? (try? withoutFraction.parse(text))
    }
}
