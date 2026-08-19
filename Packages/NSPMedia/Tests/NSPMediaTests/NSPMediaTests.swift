import Testing
@testable import NSPMedia

@Suite("NSPMedia module")
struct NSPMediaTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPMediaModule.name == "NSPMedia")
    }
}
