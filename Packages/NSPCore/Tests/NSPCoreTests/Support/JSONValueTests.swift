import Foundation
import Testing

@testable import NSPCore

@Suite("JSONValue")
struct JSONValueTests {
    @Test func test_codable_roundTripsAllCaseKinds() throws {
        let original = JSONValue.object([
            "reason": .string("user"),
            "count": .number(3),
            "ok": .bool(true),
            "tags": .array([.string("a"), .string("b")]),
            "missing": .null,
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(decoded == original)
    }
}
