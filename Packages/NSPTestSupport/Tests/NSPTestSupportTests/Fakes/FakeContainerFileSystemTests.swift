import Foundation
import NSPPersistence
import Testing

@testable import NSPTestSupport

@Suite("FakeContainerFileSystem")
struct FakeContainerFileSystemTests {
    @Test func test_createDirectory_recordsTheRequestedProtectionClass() throws {
        let fileSystem = FakeContainerFileSystem()
        let url = URL(fileURLWithPath: "/AppContainer/Meetings/m1/segments")

        try fileSystem.createDirectory(at: url, protection: .completeUnlessOpen)

        #expect(fileSystem.fileExists(at: url))
        #expect(fileSystem.protection(at: url) == .completeUnlessOpen)
    }

    @Test func test_fileExists_isFalseForAnUnrequestedURL() {
        let fileSystem = FakeContainerFileSystem()
        #expect(!fileSystem.fileExists(at: URL(fileURLWithPath: "/never/created")))
    }
}
