import Testing
@testable import NSPCore

@Suite("NSPCore module")
struct NSPCoreTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPCoreModule.name == "NSPCore")
    }
}
