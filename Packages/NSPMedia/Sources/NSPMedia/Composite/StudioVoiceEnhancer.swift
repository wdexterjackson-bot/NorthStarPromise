import AVFoundation
import Foundation

/// Typed, exhaustive error enum for `StudioVoiceEnhancer` (docs/11 §2).
public enum StudioVoiceEnhancerError: Error, Sendable, Hashable {
    case cannotOpenSourceFile
    case unsupportedChannelLayout
    case exportFailed(String)
}

/// The Audio tab's "Studio Voice" toggle: an honest, real post-process
/// pass — not a cosmetic label over nothing — that runs the same tier-3
/// spectral noise suppressor and tier-2 dynamics/AGC processor this app
/// already applies live during capture (`SpectralNoiseSuppressor`,
/// `AudioDynamicsProcessor`, docs/03 §2.6), applied here to an
/// already-recorded composite instead of a live tap. Produces one more
/// regenerable derived file (`MeetingContainer`'s `derived/` directory),
/// cached by the source file's hash exactly like `SegmentStitcher`'s own
/// composite cache — never touches the canonical segments or the raw
/// composite (Invariant I3).
public struct StudioVoiceEnhancer: Sendable {
    public init() {}

    private static let chunkFrames: AVAudioFrameCount = 8192

    /// Runs the enhancement pass and writes the result to `destinationURL`.
    /// Mono only — every segment this app records is single-channel
    /// (`docs/03`'s capture format), and both processors assume one flat
    /// sample stream; a stereo/multi-channel source is rejected rather than
    /// silently processing only its first channel.
    public func enhance(sourceURL: URL, to destinationURL: URL) throws {
        guard let sourceFile = try? AVAudioFile(forReading: sourceURL) else {
            throw StudioVoiceEnhancerError.cannotOpenSourceFile
        }
        guard sourceFile.processingFormat.channelCount == 1 else {
            throw StudioVoiceEnhancerError.unsupportedChannelLayout
        }
        let sampleRate = sourceFile.processingFormat.sampleRate

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
        ]

        do {
            let outputFile = try AVAudioFile(
                forWriting: destinationURL, settings: outputSettings, commonFormat: .pcmFormatFloat32,
                interleaved: false)
            let suppressor = SpectralNoiseSuppressor(sampleRate: sampleRate)
            let dynamics = AudioDynamicsProcessor(sampleRate: sampleRate)

            guard
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat, frameCapacity: Self.chunkFrames)
            else {
                throw StudioVoiceEnhancerError.exportFailed("Couldn't allocate a read buffer")
            }

            // Tier 3 (spectral) ahead of tier 2 (dynamics/AGC) — the same
            // order the live capture tap applies them in.
            while sourceFile.framePosition < sourceFile.length {
                try sourceFile.read(into: inputBuffer, frameCount: Self.chunkFrames)
                guard inputBuffer.frameLength > 0, let channelData = inputBuffer.floatChannelData else { break }
                let input = UnsafeBufferPointer(start: channelData[0], count: Int(inputBuffer.frameLength))
                try Self.write(suppressor.process(input), through: dynamics, to: outputFile)
            }
            try Self.write(suppressor.flush(), through: dynamics, to: outputFile)
        } catch let error as StudioVoiceEnhancerError {
            throw error
        } catch {
            throw StudioVoiceEnhancerError.exportFailed("\(error)")
        }
    }

    private static func write(
        _ samples: UnsafeBufferPointer<Float>, through dynamics: AudioDynamicsProcessor, to outputFile: AVAudioFile
    ) throws {
        guard !samples.isEmpty else { return }
        var mutable = Array(samples)
        mutable.withUnsafeMutableBufferPointer { dynamics.process($0) }

        let frameCapacity = AVAudioFrameCount(mutable.count)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFile.processingFormat, frameCapacity: frameCapacity)
        else {
            throw StudioVoiceEnhancerError.exportFailed("Couldn't allocate a write buffer")
        }
        outputBuffer.frameLength = AVAudioFrameCount(mutable.count)
        guard let channelData = outputBuffer.floatChannelData else { return }
        for i in 0..<mutable.count { channelData[0][i] = mutable[i] }
        try outputFile.write(from: outputBuffer)
    }
}
