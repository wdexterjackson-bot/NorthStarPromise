import Foundation
import NSPPersistence

/// Owns the WAL-append and seal protocols for one meeting's manifest
/// (docs/02 §4, docs/03 §3.2 step 5, §3.4; NSP-014). An actor because
/// multiple callers (segment close, timeline events) append concurrently
/// and every seal must see a consistent view — never two actors racing the
/// same `.tmp` file.
///
/// Deliberately narrow: this type does not decide *when* to append or seal
/// (the `Segmenter`, NSP-019/020, does), does not repair a torn tail (the
/// `IntegrityChecker`, NSP-021/055, does), and does not run recovery
/// end-to-end (docs/03 §5, NSP-025). It only guarantees that every
/// individual write it performs is fsync-ordered exactly as docs/03
/// specifies, and that `seal` never leaves both `manifest.json` and
/// `manifest.json.bak` invalid at once.
public actor ManifestWriter {
    private let container: MeetingContainer
    private let fileSystem: any ManifestFileSystem
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init(container: MeetingContainer, fileSystem: some ManifestFileSystem) {
        self.container = container
        self.fileSystem = fileSystem

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
    }

    private var sealTempURL: URL { container.manifestURL.appendingPathExtension("tmp") }

    /// docs/03 §3.2 step 5: one fsync'd append per event, never a full
    /// `manifest.json` rewrite.
    public func append(_ entry: ManifestWALEntry) throws {
        var data = try jsonEncoder.encode(entry)
        data.append(0x0A)
        try fileSystem.appendAndFsync(data, to: container.manifestWALURL)
    }

    /// docs/03 §3.4, in order: write `manifest.json.tmp` and fsync, copy the
    /// current `manifest.json` to `.bak` (skipped the very first time, when
    /// there is nothing to preserve), rename `.tmp` over `manifest.json`,
    /// fsync the containing directory, then truncate the WAL. Every one of
    /// these five steps is independently killable — NSP-014's acceptance —
    /// and none of them, alone or interrupted, can leave both
    /// `manifest.json` and `manifest.json.bak` invalid.
    public func seal(_ manifest: Manifest, sealedAt: Date) throws {
        var sealed = manifest
        sealed.sealedAt = sealedAt
        sealed.integrity.sealed = true

        let data = try jsonEncoder.encode(sealed)
        try fileSystem.writeAndFsync(data, to: sealTempURL)

        if fileSystem.fileExists(at: container.manifestURL) {
            try fileSystem.copyItem(at: container.manifestURL, to: container.manifestBackupURL)
        }

        try fileSystem.renameItem(at: sealTempURL, to: container.manifestURL)
        try fileSystem.fsyncDirectory(at: container.rootURL)
        try fileSystem.truncate(at: container.manifestWALURL)
    }

    /// Loads `manifest.json` if present, falling back to `.bak` when the
    /// primary is missing or fails `Manifest.validates()` — the
    /// double-buffer recovery reads on (docs/03 §5).
    public func loadCurrentManifest() throws -> Manifest? {
        if let manifest = try loadManifest(at: container.manifestURL), manifest.validates() {
            return manifest
        }
        if let manifest = try loadManifest(at: container.manifestBackupURL), manifest.validates() {
            return manifest
        }
        return nil
    }

    /// Replays every complete entry in `manifest.wal`, in append order. A
    /// trailing partial line — the signature of a crash mid-append — is
    /// silently dropped rather than treated as corruption; recovery already
    /// knows the tail may be short (docs/03 §3.2, §3.5).
    public func replayWAL() throws -> [ManifestWALEntry] {
        guard fileSystem.fileExists(at: container.manifestWALURL) else { return [] }
        let data = try fileSystem.readData(at: container.manifestWALURL)

        var entries: [ManifestWALEntry] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let entry = try? jsonDecoder.decode(ManifestWALEntry.self, from: Data(line)) else { continue }
            entries.append(entry)
        }
        return entries
    }

    private func loadManifest(at url: URL) throws -> Manifest? {
        guard fileSystem.fileExists(at: url) else { return nil }
        let data = try fileSystem.readData(at: url)
        return try? jsonDecoder.decode(Manifest.self, from: data)
    }
}
