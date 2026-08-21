import AVFoundation
import Foundation
import NSPCore
import NSPMedia
import NSPPersistence
import NSPTestSupport
import Testing

@testable import NSPIntelligence

/// A real end-to-end check of whether on-device transcription actually
/// works in *this* Simulator right now — not a mock. Runs the real
/// `LiveTranscriber` (real `SFSpeechRecognizer`) against a real recorded
/// speech fixture (`Fixtures/speech-test.wav`, generated via macOS `say`,
/// so its content is known and non-silent), imported through the same
/// `AudioFileImporter` path a live recording or a Voice Memos import uses.
/// Runs only in the app's own test target (`NorthStarPhoneTests`, driven by
/// `xcodebuild test` against an iOS Simulator destination) rather than a
/// package's `swift test`, because `swift test` builds for the host Mac,
/// not the Simulator — the whole point here is to observe the Simulator's
/// own on-device speech model availability, not the host's.
@Suite("Transcription — real Simulator check")
struct TranscriptionSimulatorTests {
    @Test("LiveTranscriber produces at least one turn for a real speech fixture")
    func test_liveTranscriber_realSpeechFixture_producesTurns() async throws {
        let fixtureURL = try #require(
            Bundle(for: BundleToken.self).url(forResource: "speech-test", withExtension: "wav"),
            "speech-test.wav fixture missing from the test bundle")

        let meetingID = MeetingID(rawValue: UUID())
        let deviceID = DeviceID(rawValue: UUID())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionSimulatorTests-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: meetingID)
        try container.ensureDirectoryStructure(using: LiveContainerFileSystem())

        let manifestWriter = ManifestWriter(container: container, fileSystem: LiveManifestFileSystem())
        let segmentRepository = FakeSegmentRepository()
        let importer = AudioFileImporter(
            audioEncoder: AVAudioFileSegmentEncoder(), segmentFileSystem: LiveSegmentFileSystem(),
            segmentRepository: segmentRepository, clock: FixedClock())

        let manifest = try await importer.importFile(
            at: fixtureURL, meetingID: meetingID, deviceID: deviceID, container: container,
            manifestWriter: manifestWriter)
        let segment = try #require(try await segmentRepository.fetchAll(owner: .meeting(meetingID)).first)
        #expect(manifest.segments.count == 1)

        let request = TranscriptionRequest(
            meetingID: meetingID,
            segments: [SegmentRef(segmentID: segment.segmentID, deviceID: deviceID, sequence: 0)],
            expectedLanguages: [Locale.Language(identifier: "en-US")])
        let transcriber = LiveTranscriber(segmentRepository: segmentRepository)
        let result = try await transcriber.transcribeOnDevice(request)
        let recognizedText = result.turns.flatMap(\.tokens).map(\.text).joined(separator: " ")

        #if targetEnvironment(simulator)
            // The Simulator's on-device speech service
            // (`com.apple.speech.localspeechrecognition`) fails to
            // initialize at all — a long-standing platform limitation, not
            // something this app's code can work around, and not
            // reliably predictable from `SFSpeechRecognizer.isAvailable`
            // ahead of time (it reports `true` right up until the actual
            // recognition task fails with `kLSRErrorDomain` code 300). Per
            // this repo's own hardware validation gate (`CLAUDE.md` §7):
            // "Anything that claims 'recording works' must be validated on
            // physical hardware" — this assertion only really runs there.
            withKnownIssue("On-device speech recognition doesn't run in the Simulator — validate on hardware") {
                #expect(!result.turns.isEmpty)
            }
        #else
            #expect(
                !result.turns.isEmpty, "Expected at least one transcript turn; got zero — recognizedText was empty")
            #expect(
                recognizedText.lowercased().contains("fox") || recognizedText.lowercased().contains("test"),
                "Recognized text didn't contain an expected word — got: \"\(recognizedText)\"")
        #endif
    }
}

private final class BundleToken {}

private struct FixedClock: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }
}
