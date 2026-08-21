@preconcurrency import AVFoundation
import Foundation
import NSPCore
import NSPPersistence

/// Typed, exhaustive error enum for `AudioFileImporter` (docs/11 §2).
public enum AudioFileImporterError: Error, Sendable, Hashable {
    case cannotOpenSourceFile
    case cannotCreateConverter
    case conversionFailed
    case emptySourceFile
}

/// Imports an existing audio file (a Voice Memos export, another
/// recorder's `.mp3`/`.wav`/`.m4a`) as a meeting's one and only segment —
/// reusing the exact atomic-close/seal protocol `Segmenter`'s live-capture
/// path uses (docs/03 §3.2, §3.4: encode → fsync → hash → atomic rename →
/// WAL append → seal), just without the rotation logic a live session
/// needs, since an import has its whole duration up front. `AVAudioFile`'s
/// read side decodes any of those source codecs to PCM automatically;
/// `AVAudioConverter` resamples/downmixes that PCM to this app's canonical
/// segment format before re-encoding — I1/I3 hold by construction, not by
/// convention, because this is the same durability path a live recording
/// uses, not a shortcut around it.
public struct AudioFileImporter: Sendable {
    private let audioEncoder: any SegmentAudioEncoder
    private let segmentFileSystem: any SegmentFileSystem
    private let segmentRepository: any SegmentRepository
    private let clock: any Clock

    public init(
        audioEncoder: any SegmentAudioEncoder, segmentFileSystem: any SegmentFileSystem,
        segmentRepository: any SegmentRepository, clock: any Clock
    ) {
        self.audioEncoder = audioEncoder
        self.segmentFileSystem = segmentFileSystem
        self.segmentRepository = segmentRepository
        self.clock = clock
    }

    /// Reads `sourceURL` start to finish, re-encodes it into the
    /// container's single segment (sequence 0), persists the `Segment` row,
    /// and returns the sealed `Manifest` — the same return shape
    /// `CaptureEngine.stop()` hands back for a live recording, so callers
    /// (`AudioImportCoordinator`) treat the two identically from here on.
    public func importFile(
        at sourceURL: URL, meetingID: MeetingID, deviceID: DeviceID, container: MeetingContainer,
        manifestWriter: ManifestWriter, targetFormat: SegmentAudioFormat = .iOSDefault
    ) async throws -> Manifest {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        guard sourceFile.length > 0 else { throw AudioFileImporterError.emptySourceFile }

        guard
            let targetAVFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(targetFormat.sampleRate),
                channels: AVAudioChannelCount(targetFormat.channels), interleaved: false),
            let converter = AVAudioConverter(from: sourceFile.processingFormat, to: targetAVFormat)
        else {
            throw AudioFileImporterError.cannotCreateConverter
        }

        let inFlightURL = container.inFlightSegmentURL(sequence: 0)
        let finalURL = container.segmentURL(sequence: 0)
        try audioEncoder.startSegment(at: inFlightURL, format: targetFormat)
        // The header alone, fsync'd before any frame arrives — matches
        // `Segmenter.openSegment()`'s own "armed-but-empty is still valid"
        // step (docs/03 §3.2).
        try segmentFileSystem.fsync(at: inFlightURL)

        let totalSampleCount = try await encodeAllFrames(
            from: sourceFile, converter: converter, targetFormat: targetAVFormat)

        try audioEncoder.finishWriting()
        try segmentFileSystem.fsync(at: inFlightURL)
        let sha256 = try segmentFileSystem.sha256(ofFileAt: inFlightURL)
        try segmentFileSystem.renameItem(at: inFlightURL, to: finalURL)

        let segmentID = SegmentID(rawValue: UUID())
        let closedAt = clock.now()
        let record = ManifestSegmentRecord(
            sequence: 0, segmentID: segmentID, file: "segments/\(finalURL.lastPathComponent)", startSample: 0,
            sampleCount: totalSampleCount, sha256: sha256, closedAt: closedAt)
        try await manifestWriter.append(.segment(record))

        let segment = Segment(
            segmentID: segmentID, owner: .meeting(meetingID), deviceID: deviceID, sequence: 0,
            codec: targetFormat.codec,
            sampleRate: targetFormat.sampleRate, channels: targetFormat.channels, bitRate: targetFormat.bitRate,
            startSample: 0, sampleCount: totalSampleCount, sha256: sha256, localURL: finalURL,
            transferState: .local)
        try await segmentRepository.insert(segment, at: closedAt)

        var manifest = Manifest(
            owner: .meeting(meetingID), deviceID: deviceID, captureMode: .import,
            audioFormat: Manifest.AudioFormat(
                codec: targetFormat.codec, sampleRate: targetFormat.sampleRate, channels: targetFormat.channels,
                bitRate: targetFormat.bitRate),
            createdAt: closedAt, segments: [record])
        try await manifestWriter.seal(manifest, sealedAt: closedAt)
        // `seal` writes its own sealed copy to disk; mirror that mutation
        // here so the value this call returns matches what was persisted,
        // rather than the pre-seal draft (same pattern as `Segmenter.stop()`).
        manifest.sealedAt = closedAt
        manifest.integrity.sealed = true
        return manifest
    }

    /// Reads the source file in chunks, converts each to the target format,
    /// and appends the resulting samples to the already-open encoder —
    /// pulled out of `importFile` purely to keep that under this repo's
    /// 50-line function-body budget.
    private func encodeAllFrames(
        from sourceFile: AVAudioFile, converter: AVAudioConverter, targetFormat: AVAudioFormat
    ) async throws -> Int64 {
        var totalSampleCount: Int64 = 0
        let readChunkFrames: AVAudioFrameCount = 65536

        while sourceFile.framePosition < sourceFile.length {
            guard
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat, frameCapacity: readChunkFrames)
            else {
                throw AudioFileImporterError.cannotCreateConverter
            }
            // Reading exactly at end-of-file throws rather than returning a
            // zero-length buffer for some compressed source codecs (AAC in
            // particular) — checking `framePosition` against `length` before
            // each read avoids ever making that trailing call, rather than
            // relying on a post-read length check to detect EOF.
            try sourceFile.read(into: inputBuffer, frameCount: readChunkFrames)
            if inputBuffer.frameLength == 0 { break }

            let ratio = targetFormat.sampleRate / sourceFile.processingFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 16
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                throw AudioFileImporterError.cannotCreateConverter
            }

            // `AVAudioConverter.convert`'s pull block runs synchronously,
            // inline, on this same thread — not actually concurrent despite
            // the imported ObjC signature's `@Sendable` inference.
            // `nonisolated(unsafe)` documents that rather than fighting it.
            nonisolated(unsafe) var hasSuppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if hasSuppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                hasSuppliedInput = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if let conversionError { throw conversionError }
            guard status != .error else { throw AudioFileImporterError.conversionFailed }

            if outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData {
                let samples = Array(
                    UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
                try audioEncoder.append(samples)
                totalSampleCount += Int64(samples.count)
            }
        }
        return totalSampleCount
    }
}
