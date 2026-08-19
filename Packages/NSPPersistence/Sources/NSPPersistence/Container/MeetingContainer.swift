import Foundation
import NSPCore

/// The on-disk layout for one meeting (docs/02 §4, verbatim):
///
/// ```
/// <AppContainer>/Meetings/<meetingID>/
/// ├── manifest.json          current sealed manifest
/// ├── manifest.json.bak      previous sealed manifest (double-buffered)
/// ├── manifest.wal           append-only event log since last seal
/// ├── segments/
/// │   ├── 000000.m4a         immutable, named by sequence, hash in manifest
/// │   └── .tmp-000002.m4a    in-flight; recovery inspects and repairs or discards these
/// ├── ink/                   PencilKit drawing assets, referenced by NoteBlock
/// ├── attachments/           photos, scans, imported files
/// └── derived/               waveform peaks, chapter thumbnails — regenerable, never authoritative
/// ```
///
/// This type only computes paths and creates the directory tree with the
/// right Data Protection class per docs/06 §4 — `manifest.json`/`.bak`/
/// `.wal` and segment files themselves are written by `NSPMedia`'s
/// `ManifestWriter`/`Segmenter` (NSP-014), not here.
public struct MeetingContainer: Sendable {
    public let meetingID: MeetingID
    public let rootURL: URL

    public init(appContainerURL: URL, meetingID: MeetingID) {
        self.meetingID = meetingID
        self.rootURL =
            appContainerURL
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent(meetingID.rawValue.uuidString, isDirectory: true)
    }

    public var manifestURL: URL { rootURL.appendingPathComponent("manifest.json") }
    public var manifestBackupURL: URL { rootURL.appendingPathComponent("manifest.json.bak") }
    public var manifestWALURL: URL { rootURL.appendingPathComponent("manifest.wal") }
    public var segmentsDirectoryURL: URL { rootURL.appendingPathComponent("segments", isDirectory: true) }
    public var inkDirectoryURL: URL { rootURL.appendingPathComponent("ink", isDirectory: true) }
    public var attachmentsDirectoryURL: URL { rootURL.appendingPathComponent("attachments", isDirectory: true) }
    public var derivedDirectoryURL: URL { rootURL.appendingPathComponent("derived", isDirectory: true) }

    /// The final name for a closed segment — immutable and content-addressed
    /// (Invariant I3); `sequence` is zero-padded to six digits, matching the
    /// docs/02 §4 example (`000000.m4a`).
    public func segmentURL(sequence: Int) -> URL {
        segmentsDirectoryURL.appendingPathComponent(String(format: "%06d.m4a", sequence))
    }

    /// The in-flight name before the atomic close protocol renames it
    /// (docs/03 §3.2) — recovery inspects and repairs or discards these.
    public func inFlightSegmentURL(sequence: Int) -> URL {
        segmentsDirectoryURL.appendingPathComponent(String(format: ".tmp-%06d.m4a", sequence))
    }

    /// Creates every directory in the layout above with the protection
    /// class docs/06 §4 assigns it. Idempotent — safe to call on every
    /// launch, not just meeting creation.
    public func ensureDirectoryStructure(using fileSystem: some ContainerFileSystem) throws {
        // The root and `segments/` hold files that must stay writable while
        // the device is locked (wrist-down recording); `derived/` too, since
        // waveform generation is convenience work that shouldn't need an
        // unlock. `ink/` and `attachments/` have no such requirement.
        try fileSystem.createDirectory(at: rootURL, protection: .completeUnlessOpen)
        try fileSystem.createDirectory(at: segmentsDirectoryURL, protection: .completeUnlessOpen)
        try fileSystem.createDirectory(at: derivedDirectoryURL, protection: .completeUnlessOpen)
        try fileSystem.createDirectory(at: inkDirectoryURL, protection: .complete)
        try fileSystem.createDirectory(at: attachmentsDirectoryURL, protection: .complete)
    }
}
