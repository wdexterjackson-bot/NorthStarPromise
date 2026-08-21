import AVFoundation
import Foundation
import NSPCore
import Testing

@testable import NSPMedia

/// Covers the Audio tab's Voice-Memos-parity building blocks
/// (`WaveformPeakExtractor`, `AudioClipExporter`, `StudioVoiceEnhancer`) —
/// real, tiny mono `.m4a` fixtures, same reasoning `SegmentStitcherTests`
/// documents for its own fixtures: these types really decode/encode
/// through `AVFoundation`, so a fake byte stream can't stand in.
@Suite("Audio enhancement — waveform, trim export, Studio Voice")
struct AudioEnhancementTests {
    private static let format = SegmentAudioFormat(codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000)

    private static func writeFixture(at url: URL, durationSeconds: Double = 1.0) throws {
        let sampleCount = Int(durationSeconds * Double(format.sampleRate))
        var samples = [Float](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let t = Double(index) / Double(format.sampleRate)
            samples[index] = Float(sin(2 * Double.pi * 440 * t)) * 0.5
        }
        let encoder = AVAudioFileSegmentEncoder()
        try encoder.startSegment(at: url, format: format)
        try encoder.append(samples)
        try encoder.finishWriting()
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioEnhancementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func duration(ofFileAt url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    @Test("peaks(from:bucketCount:) returns exactly bucketCount non-negative values, not all zero for a real tone")
    func test_waveformPeakExtractor_producesRequestedBucketCount() throws {
        let root = try Self.makeTempDirectory()
        let sourceURL = root.appendingPathComponent("source.m4a")
        try Self.writeFixture(at: sourceURL)

        let peaks = try WaveformPeakExtractor().peaks(from: sourceURL, bucketCount: 40)

        #expect(peaks.count == 40)
        #expect(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(peaks.contains { $0 > 0 })
    }

    @Test("peaks(from:bucketCount:) throws for a nonexistent file")
    func test_waveformPeakExtractor_missingFile_throws() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).m4a")
        #expect(throws: Error.self) {
            try WaveformPeakExtractor().peaks(from: missingURL, bucketCount: 10)
        }
    }

    @Test("exportClip writes a shorter file spanning roughly the requested sample range")
    func test_audioClipExporter_exportsTheRequestedRange() throws {
        let root = try Self.makeTempDirectory()
        let sourceURL = root.appendingPathComponent("source.m4a")
        try Self.writeFixture(at: sourceURL, durationSeconds: 2.0)
        let clipURL = root.appendingPathComponent("clip.m4a")

        let sampleRate = Self.format.sampleRate
        try AudioClipExporter().exportClip(
            from: sourceURL, startSample: Int64(sampleRate / 2), endSample: Int64(sampleRate), to: clipURL)

        #expect(FileManager.default.fileExists(atPath: clipURL.path))
        let clipDuration = try Self.duration(ofFileAt: clipURL)
        // ~0.5s requested; AAC encoder priming/padding means "close to," not exact.
        #expect(abs(clipDuration - 0.5) < 0.1)
    }

    @Test("exportClip rejects an out-of-bounds range")
    func test_audioClipExporter_invalidRange_throws() throws {
        let root = try Self.makeTempDirectory()
        let sourceURL = root.appendingPathComponent("source.m4a")
        try Self.writeFixture(at: sourceURL, durationSeconds: 1.0)
        let clipURL = root.appendingPathComponent("clip.m4a")

        #expect(throws: Error.self) {
            try AudioClipExporter().exportClip(from: sourceURL, startSample: 0, endSample: 999_999_999, to: clipURL)
        }
    }

    @Test("enhance produces a playable file of roughly the same duration as the source")
    func test_studioVoiceEnhancer_producesAnEnhancedFileOfSimilarDuration() throws {
        let root = try Self.makeTempDirectory()
        let sourceURL = root.appendingPathComponent("source.m4a")
        try Self.writeFixture(at: sourceURL, durationSeconds: 1.0)
        let enhancedURL = root.appendingPathComponent("studio.m4a")

        try StudioVoiceEnhancer().enhance(sourceURL: sourceURL, to: enhancedURL)

        #expect(FileManager.default.fileExists(atPath: enhancedURL.path))
        let enhancedDuration = try Self.duration(ofFileAt: enhancedURL)
        #expect(abs(enhancedDuration - 1.0) < 0.15)
    }
}
