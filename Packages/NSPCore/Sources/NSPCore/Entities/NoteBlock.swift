/// A note block's payload — either text runs or a reference to an asset
/// (ink, photo) stored outside the database (docs/02 §1, "media lives in
/// files"; docs/02 §2, `NoteBlock.content`).
public enum BlockContent: Sendable, Hashable, Codable {
    case text(String)
    case assetReference(path: String)
}

/// One entry in a note block's conflict-resilient operation log
/// (docs/02 §2, `NoteBlock.opLog`; v1 merge strategy is last-writer-wins per
/// block with operation logs, not full CRDT — docs/00 §5).
public struct Operation: Sendable, Hashable, Codable {
    public let authorID: PersonID
    public let timestamp: Int64
    public let content: BlockContent

    public init(authorID: PersonID, timestamp: Int64, content: BlockContent) {
        self.authorID = authorID
        self.timestamp = timestamp
        self.content = content
    }
}

/// A typed or handwritten note. AI never mutates a `NoteBlock` — it may only
/// propose a merge that produces a diff the user approves (docs/02 §2).
public struct NoteBlock: Sendable, Hashable, Codable, Identifiable {
    public let blockID: NoteBlockID
    public var id: NoteBlockID { blockID }
    public let owner: ContentOwnerRef
    public let authorID: PersonID

    public let type: NoteBlockType
    public var content: BlockContent

    /// Sample range during which this block was authored — what makes
    /// tap-to-replay work.
    public let creationRange: SampleRange
    public var privacy: BlockPrivacy
    public var mergeState: MergeState
    public var opLog: [Operation]

    public init(
        blockID: NoteBlockID,
        owner: ContentOwnerRef,
        authorID: PersonID,
        type: NoteBlockType,
        content: BlockContent,
        creationRange: SampleRange,
        privacy: BlockPrivacy = .privateToAuthor,
        mergeState: MergeState = .standalone,
        opLog: [Operation] = []
    ) {
        self.blockID = blockID
        self.owner = owner
        self.authorID = authorID
        self.type = type
        self.content = content
        self.creationRange = creationRange
        self.privacy = privacy
        self.mergeState = mergeState
        self.opLog = opLog
    }
}
