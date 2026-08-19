import Testing
@testable import NSPPolicy

@Suite("NSPPolicy module")
struct NSPPolicyTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPPolicyModule.name == "NSPPolicy")
    }
}
