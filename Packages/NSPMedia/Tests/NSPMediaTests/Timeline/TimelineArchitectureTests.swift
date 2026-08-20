import Foundation
import Testing

/// TC-CAP-013 (docs/03 §13, NSP-025): "proves no `Date()`/`Timer` in
/// timeline code." Scans every source file under `Timeline/` for the
/// literal construction calls — `Date` and `Timer` as *types* are fine
/// (`DeviceAnchor.sampleZeroWallClock: Date` is caller-supplied data, not a
/// clock read); it's calling `Date()` or constructing a `Timer` that reads
/// or schedules against the clock this type must never do (docs/03 §4).
@Suite("TC-CAP-013 — no Date()/Timer in timeline code")
struct TimelineArchitectureTests {
    private static var timelineDirectory: URL {
        // This file lives at Packages/NSPMedia/Tests/NSPMediaTests/Timeline/TimelineArchitectureTests.swift;
        // walk up four levels to Packages/NSPMedia, then down into Sources/NSPMedia/Timeline.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NSPMedia/Timeline", isDirectory: true)
    }

    @Test func test_timelineSources_neverConstructDateOrTimer() {
        guard
            let enumerator = FileManager.default.enumerator(
                at: Self.timelineDirectory, includingPropertiesForKeys: nil)
        else {
            Issue.record("could not enumerate \(Self.timelineDirectory.path)")
            return
        }

        var scannedAtLeastOneFile = false
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scannedAtLeastOneFile = true

            #expect(
                !contents.contains("Date()"),
                "\(url.lastPathComponent) calls Date() — timeline math must never read the wall clock")
            #expect(
                !contents.contains("Timer("),
                "\(url.lastPathComponent) constructs a Timer — timeline math must never schedule against the wall clock"
            )
        }

        #expect(scannedAtLeastOneFile, "no .swift files found under \(Self.timelineDirectory.path)")
    }
}
