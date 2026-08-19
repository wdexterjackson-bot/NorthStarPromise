import Testing
@testable import NSPSync

@Suite("NSPSync module")
struct NSPSyncTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPSyncModule.name == "NSPSync")
    }
}
