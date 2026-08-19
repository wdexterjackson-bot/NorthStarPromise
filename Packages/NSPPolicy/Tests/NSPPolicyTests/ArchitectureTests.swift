import Foundation
import Testing

/// POL-002 — "ProcessingGrant cannot be constructed outside NSPPolicy."
/// `ProcessingGrant.init` is already `internal`, so the compiler already
/// enforces this; this test is a regression guard against someone widening
/// that access level later, and reuses the source-scan pattern from
/// `NSPCoreTests/ArchitectureTests.swift` rather than re-deriving it.
@Suite("POL-002 gate — architecture")
struct ArchitectureTests {
    struct SourceFile {
        let path: String
        let packageName: String?
        let contents: String
    }

    static var repoRoot: URL {
        // This file lives at Packages/NSPPolicy/Tests/NSPPolicyTests/ArchitectureTests.swift;
        // walk up five levels to the repo root.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func swiftFiles(under directory: String) -> [SourceFile] {
        let root = repoRoot.appendingPathComponent(directory)
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }

        var files: [SourceFile] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = url.path(percentEncoded: false)
            files.append(SourceFile(path: path, packageName: packageName(forPath: path), contents: contents))
        }
        return files
    }

    static func packageName(forPath path: String) -> String? {
        guard let range = path.range(of: "Packages/") else { return nil }
        let afterPackages = path[range.upperBound...]
        return afterPackages.split(separator: "/").first.map(String.init)
    }

    @Test func test_processingGrant_isConstructedOnlyInsideNSPPolicy() {
        let files = Self.swiftFiles(under: "Packages") + Self.swiftFiles(under: "App")

        for file in files {
            guard file.packageName != "NSPPolicy" else { continue }
            #expect(
                !file.contents.contains("ProcessingGrant("),
                "\(file.path) constructs ProcessingGrant, but only NSPPolicy may (POL-002)"
            )
        }
    }
}
