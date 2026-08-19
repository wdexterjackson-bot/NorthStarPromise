import Foundation
import NSPCore
import Testing

@testable import NSPPersistence

/// Local to this test target — `NSPTestSupport` depends on `NSPPersistence`,
/// so importing a fake back from there would be circular.
private final class TestFakeContainerFileSystem: ContainerFileSystem, @unchecked Sendable {
    private(set) var createdDirectories: [URL: DataProtectionClass] = [:]

    func createDirectory(at url: URL, protection: DataProtectionClass) throws {
        createdDirectories[url] = protection
    }

    func fileExists(at url: URL) -> Bool {
        createdDirectories[url] != nil
    }
}

@Suite("MeetingContainer")
struct MeetingContainerTests {
    private static func makeContainer() -> (container: MeetingContainer, appRoot: URL) {
        let appRoot = URL(fileURLWithPath: "/AppContainer")
        let meetingID = MeetingID(rawValue: UUID(uuidString: "AAAAAAAA-0000-7000-8000-000000000000")!)
        return (MeetingContainer(appContainerURL: appRoot, meetingID: meetingID), appRoot)
    }

    @Test func test_paths_matchTheDocumentedLayout() {
        let (container, appRoot) = Self.makeContainer()
        let expectedRoot =
            appRoot
            .appendingPathComponent("Meetings", isDirectory: true)
            .appendingPathComponent("AAAAAAAA-0000-7000-8000-000000000000", isDirectory: true)

        #expect(container.rootURL == expectedRoot)
        #expect(container.manifestURL == expectedRoot.appendingPathComponent("manifest.json"))
        #expect(container.manifestBackupURL == expectedRoot.appendingPathComponent("manifest.json.bak"))
        #expect(container.manifestWALURL == expectedRoot.appendingPathComponent("manifest.wal"))
        #expect(container.segmentsDirectoryURL == expectedRoot.appendingPathComponent("segments", isDirectory: true))
        #expect(container.inkDirectoryURL == expectedRoot.appendingPathComponent("ink", isDirectory: true))
        #expect(
            container.attachmentsDirectoryURL == expectedRoot.appendingPathComponent("attachments", isDirectory: true))
        #expect(container.derivedDirectoryURL == expectedRoot.appendingPathComponent("derived", isDirectory: true))
    }

    @Test func test_segmentURL_isZeroPaddedAndImmutablyNamed() {
        let (container, _) = Self.makeContainer()
        #expect(container.segmentURL(sequence: 0).lastPathComponent == "000000.m4a")
        #expect(container.segmentURL(sequence: 42).lastPathComponent == "000042.m4a")
        #expect(container.inFlightSegmentURL(sequence: 2).lastPathComponent == ".tmp-000002.m4a")
    }

    @Test func test_ensureDirectoryStructure_requestsTheDocumentedProtectionClassPerDirectory() throws {
        let (container, _) = Self.makeContainer()
        let fileSystem = TestFakeContainerFileSystem()

        try container.ensureDirectoryStructure(using: fileSystem)

        // docs/06 §4: segments/manifest/derived stay writable while locked;
        // ink/attachments don't need to.
        #expect(fileSystem.createdDirectories[container.rootURL] == .completeUnlessOpen)
        #expect(fileSystem.createdDirectories[container.segmentsDirectoryURL] == .completeUnlessOpen)
        #expect(fileSystem.createdDirectories[container.derivedDirectoryURL] == .completeUnlessOpen)
        #expect(fileSystem.createdDirectories[container.inkDirectoryURL] == .complete)
        #expect(fileSystem.createdDirectories[container.attachmentsDirectoryURL] == .complete)
    }

    @Test func test_liveContainerFileSystem_actuallyCreatesTheDirectoryTreeOnDisk() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nsp-container-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let meetingID = MeetingID(rawValue: UUID())
        let container = MeetingContainer(appContainerURL: tempRoot, meetingID: meetingID)
        let fileSystem = LiveContainerFileSystem()

        try container.ensureDirectoryStructure(using: fileSystem)

        var isDirectory: ObjCBool = false
        for url in [
            container.rootURL, container.segmentsDirectoryURL, container.inkDirectoryURL,
            container.attachmentsDirectoryURL, container.derivedDirectoryURL,
        ] {
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            #expect(exists, "expected \(url.path) to exist")
            #expect(isDirectory.boolValue, "expected \(url.path) to be a directory")
        }
    }
}
