import Foundation
import Testing

@testable import NSPMedia

@Suite("InkAssetFileSystem")
struct InkAssetFileSystemTests {
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InkAssetFileSystemTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("abc.drawing")
    }

    @Test func writeThenReadRoundTripsExactBytes() throws {
        let fileSystem = LiveInkAssetFileSystem()
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let data = Data("fake-pkdrawing-bytes".utf8)

        try fileSystem.write(data, to: url)

        #expect(try fileSystem.read(from: url) == data)
    }

    @Test func writeCreatesIntermediateDirectories() throws {
        let fileSystem = LiveInkAssetFileSystem()
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try fileSystem.write(Data([1, 2, 3]), to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func secondWriteOverwritesTheFirstAndLeavesNoTempFile() throws {
        let fileSystem = LiveInkAssetFileSystem()
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try fileSystem.write(Data([1, 2, 3]), to: url)
        try fileSystem.write(Data([4, 5, 6, 7]), to: url)

        #expect(try fileSystem.read(from: url) == Data([4, 5, 6, 7]))
        let siblings =
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(siblings == ["abc.drawing"])
    }
}
