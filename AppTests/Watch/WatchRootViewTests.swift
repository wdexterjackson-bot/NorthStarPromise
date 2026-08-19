import Testing

@Suite("NorthStarWatch shell")
struct WatchRootViewTests {
    @Test func test_target_compiles() {
        // Placeholder until NSP-026 (Watch capture UI) lands; proves the
        // watch app target links against the packages and its test bundle runs.
        #expect(Bool(true))
    }
}
