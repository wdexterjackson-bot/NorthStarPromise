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

    /// Reads each segment's decoded PCM straight through into one AAC
    /// output file via `AVAudioFile`, rather than `AVMutableComposition` +
    /// `AVAssetExportSession` — deliberately: the export-session pipeline
    /// depends on hardware/codec support that Simulator (and some real
    /// configurations) doesn't reliably provide, and fails there with an
    /// opaque `AVFoundationErrorDomain` code 11800 that carries no
    /// actionable detail. Reading/writing PCM buffers directly has no such
    /// dependency and is the same technique `AVAudioFileSegmentEncoder`
    /// already uses to write a segment in the first place.
    private static func export(_ segments: [Segment], to url: URL) async throws {
        #if os(watchOS)
            // `AVAudioFile`'s compressed-write path is available on
            // watchOS too, but stitched playback is phone/iPad-only UI
            // (`docs/07 §4`) — no caller on watchOS ever reaches this.
            throw SegmentStitcherError.exportFailed("Composite audio isn't supported on watchOS")
        #else
            do {
                let sourceFiles = try segments.map { segment -> AVAudioFile in
                    guard let localURL = segment.localURL else {
                        throw SegmentStitcherError.segmentUnavailableLocally(segment.segmentID)
                    }
                    return try AVAudioFile(forReading: localURL)
                }
                guard let firstFile = sourceFiles.first else { throw SegmentStitcherError.noSegments }

                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: firstFile.fileFormat.sampleRate,
                    AVNumberOfChannelsKey: firstFile.fileFormat.channelCount,
                ]
                let outputFile = try AVAudioFile(
                    forWriting: url, settings: outputSettings, commonFormat: .pcmFormatFloat32, interleaved: false)

                for sourceFile in sourceFiles {
                    try Self.copy(sourceFile, into: outputFile)
                }
            } catch let error as SegmentStitcherError {
                throw error
            } catch {
                throw SegmentStitcherError.exportFailed("\(error)")
            }
        #endif
    }

    #if !os(watchOS)
        private static let copyBufferFrameCapacity: AVAudioFrameCount = 32768

        private static func copy(_ sourceFile: AVAudioFile, into outputFile: AVAudioFile) throws {
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat, frameCapacity: Self.copyBufferFrameCapacity)
            else {
                throw SegmentStitcherError.compositionFailed("Couldn't allocate a read buffer")
            }
            while sourceFile.framePosition < sourceFile.length {
                try sourceFile.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try outputFile.write(from: buffer)
            }
        }
    #endif
}
