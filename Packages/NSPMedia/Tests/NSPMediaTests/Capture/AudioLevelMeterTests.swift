import Testing

@testable import NSPMedia

@Suite("AudioLevelMeter")
struct AudioLevelMeterTests {
    @Test func test_currentLevel_beforeAnyBuffer_isZero() {
        let meter = AudioLevelMeter()
        #expect(meter.currentLevel() == 0)
    }

    @Test func test_record_silence_staysAtTheFloor() {
        let meter = AudioLevelMeter()
        let silence = [Float](repeating: 0, count: 1024)
        silence.withUnsafeBufferPointer { meter.record(samples: $0) }
        #expect(meter.currentLevel() == 0)
    }

    @Test func test_record_fullScaleSignal_reachesTheCeiling() {
        let meter = AudioLevelMeter()
        let loud = [Float](repeating: 1.0, count: 1024)
        loud.withUnsafeBufferPointer { meter.record(samples: $0) }
        #expect(meter.currentLevel() == 1)
    }

    @Test func test_record_moderateSignal_landsStrictlyBetweenFloorAndCeiling() {
        let meter = AudioLevelMeter()
        let moderate = [Float](repeating: 0.1, count: 1024)
        moderate.withUnsafeBufferPointer { meter.record(samples: $0) }
        let level = meter.currentLevel()
        #expect(level > 0)
        #expect(level < 1)
    }

    @Test func test_record_emptyBuffer_leavesTheLevelUnchanged() {
        let meter = AudioLevelMeter()
        let moderate = [Float](repeating: 0.1, count: 1024)
        moderate.withUnsafeBufferPointer { meter.record(samples: $0) }
        let levelBefore = meter.currentLevel()

        let empty = [Float]()
        empty.withUnsafeBufferPointer { meter.record(samples: $0) }

        #expect(meter.currentLevel() == levelBefore)
    }
}
