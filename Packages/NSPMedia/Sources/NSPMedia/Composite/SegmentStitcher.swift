import AVFoundation
import Foundation
import NSPCore
import NSPPersistence

/// Typed, exhaustive error enum for `SegmentStitcher` (docs/11 §2).
public enum SegmentStitcherError: Error, Sendable, Hashable {
    case noSegments
    case mixedDevicesOrFormats
    case segmentUnavailableLocally(SegmentID)
    case compositionFailed(String)
    case exportFailed(String)
}

/// Builds one continuous, cached `.m4a` from a meeting's segments — a
/// derived, regenerable artifact under `MeetingContainer.derivedDirectoryURL`
/// (docs/02 §4: "waveform peaks, chapter thumbnails — regenerable, never
/// authoritative"), never a replacement for the segments themselves
/// (Invariant I3: segments stay the only immutable, content-addressed
/// audio). Exists so playback — and, later, docs/02 §7's M4A export — can
/// treat a meeting as one continuous recording without relaxing the short,
/// crash-safe rotation interval segments are actually captured at (docs/03
/// §3.1).
public struct SegmentStitcher: Sendable {
    public init() {}

    private static let compositeFilename = "composite.m4a"
    private static let sidecarFilename = "composite.json"

    private struct Sidecar: Codable {
        let orderedSegmentHashes: [String]
    }

    /// Builds (or reuses a valid disk cache of) one continuous `.m4a` for
    /// `segments`. Every segment must share one `deviceID` and one audio
    /// format — per docs/03 §11 a meeting only spans multiple devices via a
    /// *new linked* `Meeting` today (Watch takeover, "record separately"),
    /// never mixed segments within one `meetingID` — so this asserts that
    /// rather than silently concatenating incompatible audio. Any segment
    /// missing a local file (`.reclaimed`, never downloaded) fails the
    /// whole build rather than producing a silently-gapped composite.
    public func buildOrReuseComposite(segments: [Segment], container: MeetingContainer) async throws -> URL {
        guard !segments.isEmpty else { throw SegmentStitcherError.noSegments }
        let ordered = segments.sorted { $0.sequence < $1.sequence }
        guard Self.shareOneDeviceAndFormat(ordered) else { throw SegmentStitcherError.mixedDevicesOrFormats }

        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())
        let compositeURL = container.derivedDirectoryURL.appendingPathComponent(Self.compositeFilename)
        let sidecarURL = container.derivedDirectoryURL.appendingPathComponent(Self.sidecarFilename)
        let hashes = try Self.hexHashes(for: ordered)

        if let cached = Self.cachedURL(compositeURL: compositeURL, sidecarURL: sidecarURL, expecting: hashes) {
            return cached
        }

        let tempURL = container.derivedDirectoryURL.appendingPathComponent(".tmp-\(UUID().uuidString).m4a")
        try await Self.export(ordered, to: tempURL)

        if FileManager.default.fileExists(atPath: compositeURL.path) {
            try FileManager.default.removeItem(at: compositeURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: compositeURL)
        try JSONEncoder().encode(Sidecar(orderedSegmentHashes: hashes)).write(to: sidecarURL, options: .atomic)

        return compositeURL
    }

    private static func hexHashes(for segments: [Segment]) throws -> [String] {
        try segments.map { segment in
            guard let sha256 = segment.sha256 else {
                throw SegmentStitcherError.segmentUnavailableLocally(segment.segmentID)
            }
            return sha256.map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func cachedURL(compositeURL: URL, sidecarURL: URL, expecting hashes: [String]) -> URL? {
        guard FileManager.default.fileExists(atPath: compositeURL.path),
            let sidecarData = try? Data(contentsOf: sidecarURL),
            let sidecar = try? JSONDecoder().decode(Sidecar.self, from: sidecarData),
            sidecar.orderedSegmentHashes == hashes
        else { return nil }
        return compositeURL
    }

    private static func shareOneDeviceAndFormat(_ segments: [Segment]) -> Bool {
        guard let first = segments.first else { return false }
        return segments.allSatisfy {
            $0.deviceID == first.deviceID && $0.codec == first.codec && $0.sampleRate == first.sampleRate
                && $0.channels == first.channels
        }
    }

    private static func export(_ segments: [Segment], to url: URL) async throws {
        #if os(watchOS)
            // `AVAssetExportSession`/its presets are `API_UNAVAILABLE(watchos)`
            // — stitched playback is phone/iPad-only UI (`docs/07 §4`), so
            // this is a real, typed "not on this platform" rather than a gap.
            throw SegmentStitcherError.exportFailed("Composite audio isn't supported on watchOS")
        #else
            let composition = AVMutableComposition()
            guard
                let track = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else {
                throw SegmentStitcherError.compositionFailed("Couldn't create a composition track")
            }

            var cursor = CMTime.zero
            for segment in segments {
                guard let localURL = segment.localURL else {
                    throw SegmentStitcherError.segmentUnavailableLocally(segment.segmentID)
                }
                let asset = AVURLAsset(url: localURL)
                guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw SegmentStitcherError.compositionFailed("Segment \(segment.sequence) has no audio track")
                }
                let duration = try await asset.load(.duration)
                do {
                    try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: cursor)
                } catch {
                    throw SegmentStitcherError.compositionFailed("\(error)")
                }
                cursor = CMTimeAdd(cursor, duration)
            }

            guard
                let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
            else {
                throw SegmentStitcherError.exportFailed("Couldn't create an export session")
            }
            do {
                try await exportSession.export(to: url, as: .m4a)
            } catch {
                throw SegmentStitcherError.exportFailed("\(error)")
            }
        #endif
    }
}
