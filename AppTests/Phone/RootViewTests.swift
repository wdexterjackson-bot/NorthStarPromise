import Testing

@Suite("NorthStarPhone shell")
struct RootViewTests {
    @Test func test_target_compiles() {
        // Placeholder until NSP-037 (iPhone Today screen) lands; proves the
        // app target links against the packages and its test bundle runs.
        #expect(Bool(true))
    }
}
