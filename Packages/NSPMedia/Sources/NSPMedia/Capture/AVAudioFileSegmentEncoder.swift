import AVFoundation
import Foundation

/// Typed, exhaustive error enum for `AVAudioFileSegmentEncoder` (docs/11 §2).
public enum SegmentAudioEncoderError: Error, Sendable, Hashable {
    case noSegmentOpen
    case bufferAllocationFailed
}

/// The real `SegmentAudioEncoder`, backed by `AVAudioFile` writing
/// AAC-LC into an `.m4a` container. `AVAudioFile` accepts PCM buffers in a
/// declared "processing format" and encodes them internally to the file's
/// compressed format as each buffer is written — this is standard,
/// supported `AVFoundation` usage, not a hand-rolled encoder.
///
/// `AVAudioFile` finalizes and closes its file when deallocated, so
/// `finishWriting()` — step 1 of the atomic close protocol (docs/03 §3.2)
/// — is just releasing the reference.
public final class AVAudioFileSegmentEncoder: SegmentAudioEncoder, @unchecked Sendable {
    private let lock = NSLock()
    private var currentFile: AVAudioFile?
    private var processingFormat: AVAudioFormat?

    public init() {}

    public func startSegment(at url: URL, format: SegmentAudioFormat) throws {
        lock.lock()
        defer { lock.unlock() }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Double(format.sampleRate),
            AVNumberOfChannelsKey: format.channels,
            AVEncoderBitRateKey: format.bitRate,
        ]
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard
            let processingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(format.sampleRate),
                channels: AVAudioChannelCount(format.channels), interleaved: false)
        else {
            throw SegmentAudioEncoderError.bufferAllocationFailed
        }

        currentFile = file
        self.processingFormat = processingFormat
    }

    public func append(_ samples: [Float]) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let file = currentFile, let processingFormat else {
            throw SegmentAudioEncoderError.noSegmentOpen
        }
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
            let channelData = buffer.floatChannelData
        else {
            throw SegmentAudioEncoderError.bufferAllocationFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            channelData[0].update(from: baseAddress, count: samples.count)
        }
        try file.write(from: buffer)
    }

    public func finishWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        currentFile = nil
        processingFormat = nil
    }
}
