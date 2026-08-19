import Foundation
import Testing

@testable import NSPCore

@Suite("UUIDv7")
struct UUIDv7Tests {
    @Test func test_generate_setsVersionNibbleToSeven() {
        var generator = SystemRandomNumberGenerator()

        let uuid = UUIDv7.generate(timestamp: Date(), using: &generator)

        let versionNibble = uuid.uuid.6 >> 4
        #expect(versionNibble == 0x7)
    }

    @Test func test_generate_setsVariantBitsToRFC4122() {
        var generator = SystemRandomNumberGenerator()

        let uuid = UUIDv7.generate(timestamp: Date(), using: &generator)

        let variantBits = uuid.uuid.8 >> 6
        #expect(variantBits == 0b10)
    }
}
