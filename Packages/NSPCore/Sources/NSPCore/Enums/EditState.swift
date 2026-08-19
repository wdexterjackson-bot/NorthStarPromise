/// Who last touched a transcript turn's text or speaker attribution
/// (docs/02 §2, `TranscriptTurn.editState`).
public enum EditState: Sendable, Hashable, Codable {
    case machine
    case userEdited(revisionOf: Int)
    case userConfirmed
}
