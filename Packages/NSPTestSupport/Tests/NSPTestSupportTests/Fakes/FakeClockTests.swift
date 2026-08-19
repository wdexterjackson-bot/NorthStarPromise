import Foundation
import Testing

@testable import NSPTestSupport

@Suite("FakeClock")
struct FakeClockTests {
    @Test func test_now_returnsTheStartingDateUntilAdvanced() {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = FakeClock(startingAt: start)

        #expect(clock.now() == start)
    }

    @Test func test_advance_movesNowForwardByExactlyTheInterval() {
        let clock = FakeClock(startingAt: Date(timeIntervalSince1970: 1000))

        clock.advance(by: 60)

        #expect(clock.now() == Date(timeIntervalSince1970: 1060))
    }

    @Test func test_set_jumpsToAnArbitraryDate() {
        let clock = FakeClock()
        let target = Date(timeIntervalSince1970: 5_000_000)

        clock.set(to: target)

        #expect(clock.now() == target)
    }
}
