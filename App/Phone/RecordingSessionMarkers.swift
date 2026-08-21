import Foundation
import NSPCore
import NSPPersistence

/// Marker CRUD, split out of `RecordingSession.swift` purely to stay under
/// this repo's 400-line file budget — not a meaningful behavioral boundary,
/// same reasoning `NSPCore`'s `ExhaustiveSwitchTests` split documents for
/// its own file split.
extension RecordingSession {
    /// A marker dropped during this session — a real, editable `NoteBlock`
    /// from the moment it's created (docs/07 §4, "Markers are notes, not
    /// just timestamps"), not a bare timeline dot filled in later.
    /// `elapsedSecondsAtDrop` is wall-clock, for the in-session list's
    /// display only; `block.creationRange` carries the sample-accurate
    /// anchor that's actually persisted and used for seek/evidence.
    public struct SessionMarker: Identifiable {
        public let block: NoteBlock
        public let elapsedSecondsAtDrop: TimeInterval
        public var id: NoteBlockID { block.blockID }
    }

    /// Drops a marker and immediately creates its `NoteBlock` — empty text,
    /// so the in-session marker list (`ActiveSessionCard`) can prompt the
    /// user to label it right there, or it stays unlabeled until edited
    /// from the meeting's Notes tab later. Defaults to `.action`: a marker
    /// is almost always "flag this to follow up on," and marker text is
    /// meant to be real input to summary/action generation, not a
    /// second-class annotation (docs/07 §4).
    public func addMarker() async {
        guard state == .recording, let captureEngine, let meetingID, let selfPersonID = environment.selfPersonID
        else { return }
        do {
            let sampleOffset = try await captureEngine.addMarker(kind: .actionItem)
            let now = environment.clock.now()
            let block = NoteBlock(
                blockID: NoteBlockID(rawValue: UUID()), owner: .meeting(meetingID), authorID: selfPersonID,
                type: .action,
                content: .text(""), creationRange: SampleRange(startSample: sampleOffset, endSample: sampleOffset),
                privacy: .privateToAuthor,
                opLog: [
                    Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: .text(""))
                ])
            try await environment.noteBlockRepository.insert(block, at: now)
            markers.append(SessionMarker(block: block, elapsedSecondsAtDrop: elapsedSeconds))
        } catch {
            // A missed marker warns, never stops capture (docs/03 §2.5's
            // spirit) — surfacing that warning in the UI is a follow-up.
        }
    }

    /// Labels a marker from the in-session list. Editing an existing
    /// `NoteBlock`'s content is the same operation `NotesTab`'s composer
    /// does post-hoc — this is just that same edit, offered at the moment
    /// the user is most likely to remember what the marker was for.
    public func labelMarker(_ marker: SessionMarker, text: String) async {
        guard let index = markers.firstIndex(where: { $0.id == marker.id }), let selfPersonID = environment.selfPersonID
        else { return }
        var block = markers[index].block
        let now = environment.clock.now()
        block.content = .text(text)
        block.opLog.append(
            Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: .text(text)))
        do {
            try await environment.noteBlockRepository.update(block, at: now)
            markers[index] = SessionMarker(block: block, elapsedSecondsAtDrop: markers[index].elapsedSecondsAtDrop)
        } catch {
            // The label just doesn't stick this time; the marker itself
            // (and its timestamp) is unaffected — never worth failing the
            // recording over.
        }
    }

    public func deleteMarker(_ marker: SessionMarker) async {
        do {
            try await environment.noteBlockRepository.delete(marker.id)
            markers.removeAll { $0.id == marker.id }
        } catch {
            // Leave it in the list rather than silently pretending the
            // delete happened.
        }
    }

    static func millisecondTimestamp(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
