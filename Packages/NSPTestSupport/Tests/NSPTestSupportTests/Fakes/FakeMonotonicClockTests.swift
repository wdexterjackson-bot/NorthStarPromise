import Testing

@testable import NSPTestSupport

@Suite("FakeMonotonicClock")
struct FakeMonotonicClockTests {
    @Test func test_nowNanoseconds_startsAtTheGivenValue() {
        let clock = FakeMonotonicClock(startingAtNanoseconds: 500)

        #expect(clock.nowNanoseconds() == 500)
    }

    @Test func test_advance_isMonotonicAndExact() {
        let clock = FakeMonotonicClock()

        clock.advance(byNanoseconds: 1_000_000)
        clock.advance(byNanoseconds: 2_000_000)

        #expect(clock.nowNanoseconds() == 3_000_000)
    }
}
