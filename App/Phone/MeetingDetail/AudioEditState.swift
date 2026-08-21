import Foundation
import NSPPersistence

/// The Audio tab's per-meeting edit choices — trim range and whether
/// Studio Voice is on. A plain JSON sidecar in `MeetingContainer`'s
/// `derived/` directory, the same "regenerable, never authoritative"
/// category `SegmentStitcher`'s composite cache already lives in, rather
/// than a new database table: this is a UI preference over an existing
/// recording, not a fact about the meeting itself, and losing it just means
/// re-picking a trim range or re-enabling Studio Voice, not lost data.
struct AudioEditState: Codable, Equatable {
    var trimStartSample: Int64?
    var trimEndSample: Int64?
    var studioVoiceEnabled: Bool = false

    static let empty = AudioEditState(trimStartSample: nil, trimEndSample: nil, studioVoiceEnabled: false)

    var hasTrim: Bool { trimStartSample != nil && trimEndSample != nil }
}

enum AudioEditStateStore {
    private static let filename = "audio_edit.json"

    private static func url(for container: MeetingContainer) -> URL {
        container.derivedDirectoryURL.appendingPathComponent(filename)
    }

    static func load(container: MeetingContainer) -> AudioEditState {
        let url = url(for: container)
        guard let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(AudioEditState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    static func save(_ state: AudioEditState, container: MeetingContainer) throws {
        try FileManager.default.createDirectory(
            at: container.derivedDirectoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url(for: container), options: .atomic)
    }
}
