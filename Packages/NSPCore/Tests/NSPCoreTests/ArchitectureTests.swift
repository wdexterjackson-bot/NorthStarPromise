import Foundation
import Testing

/// The I5 code-shape gate (docs/10 §2, "I5 — Local-only means local-only",
/// gate 1 of 2: `test_architecture_networkImportsRestricted`). Parses every
/// `.swift` file under `Packages/` and `App/` and fails if a networking
/// import appears outside the allow-listed modules, or if a package imports
/// one to its right in the `CLAUDE.md` §3 dependency graph.
///
/// The behavioural half of I5 — the network-content audit against a real
/// proxy (`PRV-001`) — needs the full app and `NSPPolicy` (NSP-016, NSP-052)
/// and is scaffolded separately as a `.disabled` stub in `AppTests/Phone`.
@Suite("I5 gate — architecture")
struct ArchitectureTests {
    /// Modules allowed to import a networking framework directly
    /// (docs/10 §2: "NSPBackendClient, NSPSync, and NSPPolicy.NetworkGate").
    static let networkImportAllowList: Set<String> = ["NSPBackendClient", "NSPSync", "NSPPolicy"]

    static let networkSymbols = ["URLSession", "Network", "CloudKit"]

    /// Left-to-right dependency order from `CLAUDE.md` §3. A package may
    /// only depend on names at or before its own index, plus `NSPPolicy`
    /// and `NSPDesignSystem`, which sit outside the main chain.
    static let dependencyOrder = [
        "NSPCore", "NSPPersistence", "NSPMedia", "NSPTransfer", "NSPSync", "NSPIntelligence",
        "NSPActions",
    ]
    static let sideModules: Set<String> = ["NSPPolicy", "NSPDesignSystem", "NSPBackendClient", "NSPTestSupport"]

    struct SourceFile {
        let path: String
        let packageName: String?
        let imports: [String]
    }

    static var repoRoot: URL {
        // This file lives at Packages/NSPCore/Tests/NSPCoreTests/ArchitectureTests.swift;
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

            let imports =
                contents
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") }
                .map { $0.replacingOccurrences(of: "import ", with: "") }

            files.append(
                SourceFile(
                    path: url.path(percentEncoded: false),
                    packageName: packageName(forPath: url.path(percentEncoded: false)),
                    imports: imports))
        }
        return files
    }

    static func packageName(forPath path: String) -> String? {
        guard let range = path.range(of: "Packages/") else { return nil }
        let afterPackages = path[range.upperBound...]
        return afterPackages.split(separator: "/").first.map(String.init)
    }

    @Test func test_architecture_networkImportsRestricted() {
        let files = Self.swiftFiles(under: "Packages") + Self.swiftFiles(under: "App")

        for file in files {
            let owningModule = file.packageName ?? "App"
            guard !Self.networkImportAllowList.contains(owningModule) else { continue }

            for networkSymbol in Self.networkSymbols {
                #expect(
                    !file.imports.contains(networkSymbol),
                    "\(file.path) imports \(networkSymbol) but \(owningModule) is not in the I5 allow-list"
                )
            }
        }
    }

    @Test func test_architecture_dependencyDirection_isLeftToRightOnly() {
        let files = Self.swiftFiles(under: "Packages")

        for file in files {
            guard let owningModule = file.packageName,
                let ownIndex = Self.dependencyOrder.firstIndex(of: owningModule)
            else { continue }

            for imported in file.imports {
                guard let importedIndex = Self.dependencyOrder.firstIndex(of: imported) else {
                    continue  // not one of the main-chain modules (e.g. Foundation, NSPPolicy)
                }
                #expect(
                    importedIndex <= ownIndex,
                    "\(file.path): \(owningModule) imports \(imported), which is to its right in CLAUDE.md §3"
                )
            }
        }
    }

    #if LOCAL_ONLY
        /// NSP-017 / POL-004 — under `-DLOCAL_ONLY` (`make test LOCAL_ONLY=1`),
        /// `NSPBackendClient` itself compiles to an empty module (its own
        /// source is `#if !LOCAL_ONLY`-gated), so any remaining `import
        /// NSPBackendClient` elsewhere would fail to resolve real symbols.
        /// This is the forward-looking regression gate: it fails the moment
        /// any future ticket adds such an import, rather than waiting to
        /// discover the resulting compile error downstream.
        @Test func test_architecture_localOnly_noPackageImportsNSPBackendClient() {
            let files = Self.swiftFiles(under: "Packages") + Self.swiftFiles(under: "App")

            for file in files {
                guard file.packageName != "NSPBackendClient" else { continue }
                #expect(
                    !file.imports.contains("NSPBackendClient"),
                    "\(file.path) imports NSPBackendClient, but LocalOnly compiles it out entirely (docs/01 §4)"
                )
            }
        }
    #endif
}
