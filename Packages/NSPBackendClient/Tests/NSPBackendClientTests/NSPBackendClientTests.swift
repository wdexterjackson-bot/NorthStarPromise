import Testing
@testable import NSPBackendClient

@Suite("NSPBackendClient module")
struct NSPBackendClientTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPBackendClientModule.name == "NSPBackendClient")
    }
}
