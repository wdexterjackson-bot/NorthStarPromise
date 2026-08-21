import Foundation

/// An automatically-maintained storyline: an account, a deal, an
/// initiative, a recurring forum, or a specific 1:1 relationship
/// (`DASHBOARD_SPEC.md` §3.2). Renamed and reshaped from the former
/// `ThreadInMotion` per the Dashboard redesign scope: each meeting now
/// joins **zero or one** thread (a nullable `Meeting.threadID`), not a
/// many-to-many join table, and a thread no longer links to `Project`s —
/// the two are independent, parallel categorizations of a meeting from
/// here on.
///
/// Named `NSPThread`, not `Thread`, deliberately: `Foundation.Thread` (the
/// OS thread class) is already in scope everywhere `Foundation` is
/// imported, and this app imports it almost everywhere — a bare `Thread`
/// domain type would make every reference to either type ambiguous outside
/// this module. The `NSP` prefix is this codebase's existing convention for
/// exactly this situation (`NSPColor`, `NSPIconBadge`, etc. in
/// `NSPDesignSystem`); user-facing copy still says "Thread"/"Threads"
/// everywhere.
public struct NSPThread: Sendable, Hashable, Codable, Identifiable {
    public let threadID: NSPThreadID
    public var id: NSPThreadID { threadID }
    public let workspaceID: WorkspaceID

    public var title: String
    public var threadDescription: String?
    public var kind: ThreadKind

    /// One of `Palette.threadSlots`' six indices (0...5) — computed once at
    /// creation via `Self.colorSlot(for:)` and never recomputed, so a
    /// thread's color never drifts across relaunches (spec §2.2: "persisted
    /// on the `Thread` record at creation so it never changes").
    public var colorSlot: Int

    /// `.closed` is set directly by the user; every other case is
    /// recomputed by `ThreadStatusDeriver` wherever a thread's open
    /// actions/decisions are already loaded, then written back — this pass
    /// does not run the spec's nightly signals engine (deferred).
    public var status: NSPThreadStatus

    public var lastTouchedAt: Date
    public var nextMeetingID: MeetingID?
    /// A hard external deadline this thread tracks (a renewal, a board
    /// date) — free text for now (`"Renewal in 41 days"`'s source fact),
    /// not a modeled type; Phase 5's real pipeline is what would parse this
    /// into a structured date.
    public var externalOrgID: String?

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        threadID: NSPThreadID,
        workspaceID: WorkspaceID,
        title: String,
        threadDescription: String? = nil,
        kind: ThreadKind = .initiative,
        colorSlot: Int? = nil,
        status: NSPThreadStatus = .onTrack,
        lastTouchedAt: Date,
        nextMeetingID: MeetingID? = nil,
        externalOrgID: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.threadID = threadID
        self.workspaceID = workspaceID
        self.title = title
        self.threadDescription = threadDescription
        self.kind = kind
        self.colorSlot = colorSlot ?? Self.colorSlot(for: threadID)
        self.status = status
        self.lastTouchedAt = lastTouchedAt
        self.nextMeetingID = nextMeetingID
        self.externalOrgID = externalOrgID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A deterministic (not `Hasher`-based — `Hasher` reseeds every process
    /// launch, which would make the color change on every relaunch) FNV-1a
    /// hash of the id's bytes, reduced mod 6.
    public static func colorSlot(for id: NSPThreadID) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        withUnsafeBytes(of: id.rawValue.uuid) { buffer in
            for byte in buffer {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return Int(hash % 6)
    }
}
