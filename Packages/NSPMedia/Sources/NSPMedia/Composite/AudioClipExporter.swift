import AVFoundation
import Foundation

/// Typed, exhaustive error enum for `AudioClipExporter` (docs/11 §2).
public enum AudioClipExporterError: Error, Sendable, Hashable {
    case cannotOpenSourceFile
    case invalidRange
    case exportFailed(String)
}

/// Exports `[startSample, endSample)` of a source audio file into a new,
/// standalone `.m4a` — the Audio tab's "Share" action when a trim range is
/// set. A genuinely new derived file (`MeetingContainer`'s `derived/`
/// directory — "regenerable, never authoritative"), never a rewrite of the
/// original: Invariant I3 forbids editing a canonical segment or its
/// stitched composite in place, so a trim can only ever produce an
/// additional file alongside them, never replace anything.
public struct AudioClipExporter: Sendable {
    public init() {}

    public func exportClip(
        from sourceURL: URL, startSample: Int64, endSample: Int64, to destinationURL: URL
    ) throws {
        guard let sourceFile = try? AVAudioFile(forReading: sourceURL) else {
            throw AudioClipExporterError.cannotOpenSourceFile
        }
        guard startSample >= 0, endSample > startSample, endSample <= sourceFile.length else {
            throw AudioClipExporterError.invalidRange
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sourceFile.fileFormat.sampleRate,
            AVNumberOfChannelsKey: sourceFile.fileFormat.channelCount,
        ]
        do {
            let outputFile = try AVAudioFile(
                forWriting: destinationURL, settings: outputSettings, commonFormat: .pcmFormatFloat32,
                interleaved: false)
            sourceFile.framePosition = startSample

            let chunkFrames: AVAudioFrameCount = 32768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: chunkFrames)
            else {
                throw AudioClipExporterError.exportFailed("Couldn't allocate a read buffer")
            }

            while sourceFile.framePosition < endSample {
                let remaining = AVAudioFrameCount(endSample - sourceFile.framePosition)
                try sourceFile.read(into: buffer, frameCount: min(chunkFrames, remaining))
                guard buffer.frameLength > 0 else { break }
                try outputFile.write(from: buffer)
            }
        } catch let error as AudioClipExporterError {
            throw error
        } catch {
            throw AudioClipExporterError.exportFailed("\(error)")
        }
    }
}
