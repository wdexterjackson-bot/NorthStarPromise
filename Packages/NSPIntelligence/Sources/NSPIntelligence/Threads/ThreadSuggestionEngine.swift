import Foundation
import NSPCore

/// One action/insight/decision the engine considered — kept so a suggested
/// thread's UI can show what evidence actually drove the suggestion, not
/// just a bare title.
public struct SuggestedThreadItem: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case action(ActionID)
        case insight(InsightID)
        case decision(DecisionID)
    }

    public let kind: Kind
    public let meetingID: MeetingID
    public let text: String

    public init(kind: Kind, meetingID: MeetingID, text: String) {
        self.kind = kind
        self.meetingID = meetingID
        self.text = text
    }
}

/// A system-suggested `NSPThread` — a cluster of semantically similar open
/// action items, insights, and decisions that span *several* meetings.
/// Never auto-created — this is a suggestion the user reviews and either
/// turns into a real thread or dismisses (`ThreadsListView`'s own
/// "Suggested" section), matching this app's "suggest, human confirms"
/// pattern everywhere else generated structure could otherwise feel
/// invented (docs/07 §11). This heuristic clustering is an interim stand-in
/// for `DASHBOARD_SPEC.md` §7.3's fuller scored auto-join algorithm
/// (participant jaccard + embedding similarity + entity overlap + recency),
/// which is deferred to a later pipeline pass.
public struct SuggestedThread: Sendable, Hashable, Identifiable {
    /// A stable hash of the cluster's meeting set — identifies this
    /// suggestion for dismissal purposes even before any `NSPThreadID`
    /// exists. Two runs that surface the same meeting grouping produce the
    /// same fingerprint, so a dismissed suggestion doesn't reappear next
    /// time the list reloads.
    public var id: String { fingerprint }
    public let fingerprint: String
    public let suggestedTitle: String
    public let meetingIDs: Set<MeetingID>
    public let items: [SuggestedThreadItem]

    public init(fingerprint: String, suggestedTitle: String, meetingIDs: Set<MeetingID>, items: [SuggestedThreadItem]) {
        self.fingerprint = fingerprint
        self.suggestedTitle = suggestedTitle
        self.meetingIDs = meetingIDs
        self.items = items
    }
}

/// Clusters open actions/insights/decisions by semantic similarity via the
/// on-device embedder already used for Ask (`HybridRetriever`'s own cosine-
/// similarity math, duplicated here rather than shared — the two callers
/// score different things: chunks of transcript vs. short structured
/// bullets — and sharing a helper across packages for one small function
/// isn't worth the coupling). A cluster only becomes a suggestion once it
/// spans at least two distinct meetings; anything confined to one meeting
/// is just that meeting's own content, not a cross-cutting thread.
public enum ThreadSuggestionEngine {
    /// Similarity threshold for `NLEmbedding`'s sentence vectors — a
    /// starting point, not an empirically tuned constant (this app has no
    /// production usage data yet to tune against); revisit once real
    /// suggestion quality can be observed.
    private static let similarityThreshold: Double = 0.75

    /// Groups the three signal-source arrays `suggest` needs — collapses
    /// what would otherwise be three separate parameters (SwiftLint's
    /// `function_parameter_count` caps at 5).
    public struct SignalSources: Sendable {
        public let actions: [Action]
        public let insights: [Insight]
        public let decisions: [Decision]

        public init(actions: [Action], insights: [Insight], decisions: [Decision]) {
            self.actions = actions
            self.insights = insights
            self.decisions = decisions
        }
    }

    public static func suggest(
        _ sources: SignalSources, embedder: any EmbedderProtocol, existingThreadMeetingSets: [Set<MeetingID>],
        dismissedFingerprints: Set<String>
    ) async throws -> [SuggestedThread] {
        guard embedder.availability == .available else { return [] }
        let actions = sources.actions
        let insights = sources.insights
        let decisions = sources.decisions

        var items: [SuggestedThreadItem] = []
        // A freestanding action (`meetingID == nil`) has no meeting to
        // attach a thread suggestion to, so it's not a candidate here —
        // this engine only ever clusters *meetings* into a shared thread.
        items.append(
            contentsOf: actions.compactMap { action in
                action.meetingID.map {
                    SuggestedThreadItem(kind: .action(action.actionID), meetingID: $0, text: action.text)
                }
            })
        items.append(
            contentsOf: insights.map {
                SuggestedThreadItem(kind: .insight($0.insightID), meetingID: $0.meetingID, text: $0.text)
            })
        items.append(
            contentsOf: decisions.map {
                SuggestedThreadItem(kind: .decision($0.decisionID), meetingID: $0.meetingID, text: $0.text)
            })
        guard items.count >= 2 else { return [] }

        let vectors = try await embedder.embedOnDevice(items.map(\.text)).map(\.vector)
        guard vectors.count == items.count else { return [] }

        let clusters = Self.cluster(items: items, vectors: vectors)

        var suggestions: [SuggestedThread] = []
        for indices in clusters {
            guard indices.count >= 2 else { continue }
            let clusterItems = indices.map { items[$0] }
            let meetingIDs = Set(clusterItems.map(\.meetingID))
            guard meetingIDs.count >= 2 else { continue }
            guard !existingThreadMeetingSets.contains(where: { meetingIDs.isSubset(of: $0) }) else { continue }

            let fingerprint = Self.fingerprint(for: meetingIDs)
            guard !dismissedFingerprints.contains(fingerprint) else { continue }

            let title = Self.representativeTitle(indices: indices, vectors: vectors, items: items)
            suggestions.append(
                SuggestedThread(
                    fingerprint: fingerprint, suggestedTitle: title, meetingIDs: meetingIDs, items: clusterItems))
        }
        return suggestions
    }

    public static func fingerprint(for meetingIDs: Set<MeetingID>) -> String {
        meetingIDs.map { $0.rawValue.uuidString }.sorted().joined(separator: ",")
    }

    /// Single-linkage clustering via union-find: any two items above the
    /// threshold join the same cluster, transitively — deliberately simple
    /// (no external ML library) since the corpus size here (a workspace's
    /// open actions/insights/decisions) is small enough that O(n²) pairwise
    /// comparison is cheap.
    private static func cluster(items: [SuggestedThreadItem], vectors: [[Float]]) -> [[Int]] {
        var parent = Array(items.indices)

        func find(_ index: Int) -> Int {
            if parent[index] != index { parent[index] = find(parent[index]) }
            return parent[index]
        }
        func union(_ first: Int, _ second: Int) {
            let rootFirst = find(first)
            let rootSecond = find(second)
            if rootFirst != rootSecond { parent[rootFirst] = rootSecond }
        }

        for indexA in items.indices {
            for indexB in (indexA + 1)..<items.count where items[indexA].meetingID != items[indexB].meetingID {
                if Self.cosineSimilarity(vectors[indexA], vectors[indexB]) >= Self.similarityThreshold {
                    union(indexA, indexB)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for index in items.indices {
            groups[find(index), default: []].append(index)
        }
        return Array(groups.values)
    }

    /// The cluster member with the highest average similarity to every
    /// other member — a deterministic "most representative" pick, used as
    /// the suggestion's title rather than inventing new wording (docs/07
    /// §11: never fabricate content that isn't already real).
    private static func representativeTitle(
        indices: [Int], vectors: [[Float]], items: [SuggestedThreadItem]
    ) -> String {
        var bestIndex = indices[0]
        var bestScore = -Double.infinity
        for candidate in indices {
            var total = 0.0
            for other in indices where other != candidate {
                total += Self.cosineSimilarity(vectors[candidate], vectors[other])
            }
            let average = indices.count > 1 ? total / Double(indices.count - 1) : 0
            if average > bestScore {
                bestScore = average
                bestIndex = candidate
            }
        }
        return items[bestIndex].text
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var normLHS: Float = 0
        var normRHS: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            normLHS += lhs[index] * lhs[index]
            normRHS += rhs[index] * rhs[index]
        }
        guard normLHS > 0, normRHS > 0 else { return 0 }
        return Double(dot / (normLHS.squareRoot() * normRHS.squareRoot()))
    }
}
