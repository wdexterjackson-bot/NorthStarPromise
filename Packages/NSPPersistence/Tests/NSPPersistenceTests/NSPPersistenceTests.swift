import Testing
@testable import NSPPersistence

@Suite("NSPPersistence module")
struct NSPPersistenceTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPPersistenceModule.name == "NSPPersistence")
    }
}
