import AVFoundation
import Foundation

/// Typed, exhaustive error enum for `WaveformPeakExtractor` (docs/11 §2).
public enum WaveformPeakExtractorError: Error, Sendable, Hashable {
    case cannotOpenFile
    case emptyFile
}

/// Downsamples an audio file's PCM into a fixed number of per-bucket peak
/// (max absolute amplitude) values, `0...1` — the Audio tab's waveform
/// view reads this straight into a bar chart. Regenerable, never
/// authoritative (`MeetingContainer`'s own doc comment for `derived/`), so
/// this reads the composite fresh every time rather than trying to cache a
/// value cheap enough to recompute on every tab appearance.
public struct WaveformPeakExtractor: Sendable {
    public init() {}

    /// Reads `fileURL` start to finish and returns exactly `bucketCount`
    /// peaks, each the loudest sample's absolute value within that bucket's
    /// share of the file. `bucketCount` must be positive.
    public func peaks(from fileURL: URL, bucketCount: Int) throws -> [Float] {
        guard bucketCount > 0 else { return [] }
        guard let file = try? AVAudioFile(forReading: fileURL) else {
            throw WaveformPeakExtractorError.cannotOpenFile
        }
        guard file.length > 0 else { throw WaveformPeakExtractorError.emptyFile }

        var buckets = [Float](repeating: 0, count: bucketCount)
        let totalFrames = file.length
        let framesPerBucket = max(1, Int(totalFrames) / bucketCount)
        let readChunkFrames: AVAudioFrameCount = 32768

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: readChunkFrames) else {
            throw WaveformPeakExtractorError.cannotOpenFile
        }

        var framesReadSoFar: Int64 = 0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: readChunkFrames)
            guard buffer.frameLength > 0, let channelData = buffer.floatChannelData else { break }
            let frameLength = Int(buffer.frameLength)

            for frameIndex in 0..<frameLength {
                let globalFrame = framesReadSoFar + Int64(frameIndex)
                let bucketIndex = min(bucketCount - 1, Int(globalFrame) / framesPerBucket)
                let sample = abs(channelData[0][frameIndex])
                if sample > buckets[bucketIndex] { buckets[bucketIndex] = sample }
            }
            framesReadSoFar += Int64(frameLength)
        }

        return buckets.map { min($0, 1) }
    }
}
