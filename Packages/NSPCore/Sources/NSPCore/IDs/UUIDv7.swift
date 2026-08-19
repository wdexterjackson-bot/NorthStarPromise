import Foundation

/// Generates RFC 9562 UUIDv7 values: a 48-bit big-endian millisecond timestamp
/// followed by version/variant bits and random fill. Time-ordered so entity
/// IDs minted with `TypedID.generate` sort by creation (docs/02 §1).
enum UUIDv7 {
    static func generate(timestamp: Date, using generator: inout some RandomNumberGenerator) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)

        let millis = UInt64(max(0, timestamp.timeIntervalSince1970 * 1000))
        bytes[0] = UInt8((millis >> 40) & 0xFF)
        bytes[1] = UInt8((millis >> 32) & 0xFF)
        bytes[2] = UInt8((millis >> 24) & 0xFF)
        bytes[3] = UInt8((millis >> 16) & 0xFF)
        bytes[4] = UInt8((millis >> 8) & 0xFF)
        bytes[5] = UInt8(millis & 0xFF)

        let randA = UInt16.random(in: 0...0xFFF, using: &generator)
        bytes[6] = 0x70 | UInt8((randA >> 8) & 0x0F)  // version 0111
        bytes[7] = UInt8(randA & 0xFF)

        var randB = [UInt8](repeating: 0, count: 8)
        for i in randB.indices { randB[i] = UInt8.random(in: 0...255, using: &generator) }
        randB[0] = (randB[0] & 0x3F) | 0x80  // variant 10
        for i in 0..<8 { bytes[8 + i] = randB[i] }

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
