import Foundation
import NSPCore
import NSPMedia
import NSPPersistence
import Testing

@testable import NSPTestSupport

/// NSP-014's acceptance test: "a kill injected at any of the 40
/// instrumented points leaves a manifest that validates." Lives here
/// (rather than in `NSPMediaTests`) because it needs
/// `KillInjectingManifestFileSystem`, which — correctly — depends on
/// `NSPMedia`, not the other way around.
@Suite("NSP-014 — ManifestWriter survives a kill at any instrumented step")
struct ManifestWriterKillInjectionTests {
    /// Matches `ManifestWriter`'s own encoding exactly, so a raw decode here
    /// reflects what's actually on disk, not what a forgiving loader chose
    /// to paper over.
    private static var manifestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeContainer() -> MeetingContainer {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestWriterKillInjection-\(UUID().uuidString)", isDirectory: true)
        let container = MeetingContainer(appContainerURL: root, meetingID: MeetingID(rawValue: UUID()))
        try? FileManager.default.createDirectory(at: container.rootURL, withIntermediateDirectories: true)
        return container
    }

    private static func makeManifest(meetingID: MeetingID, deviceID: DeviceID, segmentCount: Int) -> Manifest {
        var manifest = Manifest(
            meetingID: meetingID, deviceID: deviceID, captureMode: .watch,
            audioFormat: Manifest.AudioFormat(codec: .aacLC, sampleRate: 16000, channels: 1, bitRate: 32000),
            createdAt: Date(timeIntervalSince1970: 0))
        manifest.segments = (0..<segmentCount).map { sequence in
            ManifestSegmentRecord(
                sequence: sequence, segmentID: SegmentID(rawValue: UUID()),
                file: "segments/\(String(format: "%06d", sequence)).m4a", startSample: Int64(sequence) * 1000,
                sampleCount: 1000, sha256: Data(repeating: UInt8(sequence % 256), count: 32),
                closedAt: Date(timeIntervalSince1970: 0))
        }
        return manifest
    }

    /// One 40-step realistic session (docs/03 §3.2, §3.4): an initial seal
    /// of an empty manifest — 4 steps, no `.bak` to rotate yet — then four
    /// rounds of four WAL appends followed by a seal that now does rotate
    /// `.bak` — 5 steps each. `4 + 4×(4 + 5) == 40`, matching NSP-014's "40
    /// instrumented points" exactly.
    private static func runScript(writer: ManifestWriter, meetingID: MeetingID, deviceID: DeviceID) async throws {
        try await writer.seal(
            Self.makeManifest(meetingID: meetingID, deviceID: deviceID, segmentCount: 0),
            sealedAt: Date(timeIntervalSince1970: 0))

        var segmentCount = 0
        for round in 1...4 {
            for _ in 0..<4 {
                try await writer.append(
                    .segment(
                        ManifestSegmentRecord(
                            sequence: segmentCount, segmentID: SegmentID(rawValue: UUID()),
                            file: "segments/\(String(format: "%06d", segmentCount)).m4a",
                            startSample: Int64(segmentCount) * 1000, sampleCount: 1000,
                            sha256: Data(repeating: UInt8(segmentCount % 256), count: 32),
                            closedAt: Date(timeIntervalSince1970: Double(segmentCount)))))
                segmentCount += 1
            }
            try await writer.seal(
                Self.makeManifest(meetingID: meetingID, deviceID: deviceID, segmentCount: segmentCount),
                sealedAt: Date(timeIntervalSince1970: Double(round) * 1000))
        }
    }

    @Test func test_uninterruptedScript_takesExactlyFortySteps() async throws {
        let container = Self.makeContainer()
        let killSwitch = KillInjectingManifestFileSystem(wrapping: LiveManifestFileSystem(), killAtStep: nil)
        let writer = ManifestWriter(container: container, fileSystem: killSwitch)

        try await Self.runScript(writer: writer, meetingID: container.meetingID, deviceID: DeviceID(rawValue: UUID()))

        #expect(killSwitch.stepsAttempted == 40)
    }

    @Test func test_killAtEveryStep_neverLeavesAnUnvalidatingManifestOnDisk() async throws {
        let totalSteps = 40

        for killAtStep in 1...totalSteps {
            let container = Self.makeContainer()
            defer { try? FileManager.default.removeItem(at: container.rootURL) }

            let killSwitch = KillInjectingManifestFileSystem(
                wrapping: LiveManifestFileSystem(), killAtStep: killAtStep)
            let writer = ManifestWriter(container: container, fileSystem: killSwitch)

            var caughtTheInjectedKill = false
            do {
                try await Self.runScript(
                    writer: writer, meetingID: container.meetingID, deviceID: DeviceID(rawValue: UUID()))
            } catch is KillInjectingManifestFileSystem.KillInjected {
                caughtTheInjectedKill = true
            }
            #expect(caughtTheInjectedKill, "killAtStep \(killAtStep) did not interrupt the script")

            for url in [container.manifestURL, container.manifestBackupURL] {
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let data = try Data(contentsOf: url)
                guard let manifest = try? Self.manifestDecoder.decode(Manifest.self, from: data) else {
                    // A file that exists but doesn't even decode would only
                    // occur mid-write — impossible here, since the writer
                    // only ever replaces `url`'s contents via a completed
                    // fsync'd write or an atomic rename, never a partial one.
                    let name = url.lastPathComponent as String
                    Issue.record("killAtStep \(killAtStep) left \(name) present but undecodable")
                    continue
                }
                let name = url.lastPathComponent as String
                #expect(manifest.validates(), "killAtStep \(killAtStep) left \(name) unvalidating")
            }
        }
    }
}
