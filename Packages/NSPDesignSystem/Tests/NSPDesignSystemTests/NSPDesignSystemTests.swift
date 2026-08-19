import Testing
@testable import NSPDesignSystem

@Suite("NSPDesignSystem module")
struct NSPDesignSystemTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPDesignSystemModule.name == "NSPDesignSystem")
    }
}
