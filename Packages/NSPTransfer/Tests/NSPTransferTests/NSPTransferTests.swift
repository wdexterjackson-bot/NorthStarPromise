import Testing
@testable import NSPTransfer

@Suite("NSPTransfer module")
struct NSPTransferTests {
    @Test func test_module_name_matchesPackage() {
        #expect(NSPTransferModule.name == "NSPTransfer")
    }
}
