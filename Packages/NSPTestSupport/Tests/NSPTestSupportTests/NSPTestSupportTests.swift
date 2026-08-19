import Testing
@testable import NSPTestSupport

@Suite("NSPTestSupport module")
struct NSPTestSupportTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPTestSupportModule.name == "NSPTestSupport")
    }
}
