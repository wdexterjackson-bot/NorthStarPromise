import Testing
@testable import NSPActions

@Suite("NSPActions module")
struct NSPActionsTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPActionsModule.name == "NSPActions")
    }
}
