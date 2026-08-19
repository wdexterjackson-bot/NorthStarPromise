import Testing
@testable import NSPIntelligence

@Suite("NSPIntelligence module")
struct NSPIntelligenceTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPIntelligenceModule.name == "NSPIntelligence")
    }
}
