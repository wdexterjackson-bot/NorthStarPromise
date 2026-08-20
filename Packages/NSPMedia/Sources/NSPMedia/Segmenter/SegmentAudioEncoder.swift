import Foundation
import NSPCore

/// The audio format a segment is encoded at (docs/03 §2.1's iOS/iPadOS
/// target: 48 kHz mono default, user-selectable 48 kHz stereo).
public struct SegmentAudioFormat: Sendable, Hashable {
    public let codec: AudioCodec
    public let sampleRate: Int
    public let channels: Int
    public let bitRate: Int

    public init(codec: AudioCodec, sampleRate: Int, channels: Int, bitRate: Int) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
    }

    /// docs/03 §2.1's iOS default.
    public static let iOSDefault = SegmentAudioFormat(codec: .aacLC, sampleRate: 48000, channels: 1, bitRate: 64000)
}

/// Encodes captured PCM into one segment file at a time (docs/03 §3.2 step
/// 1's "encoder"). `Segmenter` owns *when* to open/close a segment; this
/// protocol owns *how* the bytes get written — real AAC encoding on-device
/// via `AVAudioFile`, or a trivial fixture in tests. Protocol-injected so
/// `Segmenter` tests never touch a real encoder (docs/11 §4).
public protocol SegmentAudioEncoder: Sendable {
    /// Opens a new encoder writing to `url` (the in-flight
    /// `.tmp-NNNNNN.m4a` path) in `format`.
    func startSegment(at url: URL, format: SegmentAudioFormat) throws
    /// Appends already-captured mono/interleaved `Float` samples in
    /// `[-1, 1]` to the currently open segment.
    func append(_ samples: [Float]) throws
    /// Flushes the trailer and closes the file — step 1 of the atomic
    /// close protocol (docs/03 §3.2).
    func finishWriting() throws
}
