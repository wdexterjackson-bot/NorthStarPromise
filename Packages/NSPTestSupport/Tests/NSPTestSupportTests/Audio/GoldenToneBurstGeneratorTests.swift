import Testing

@testable import NSPTestSupport

@Suite("GoldenToneBurstGenerator")
struct GoldenToneBurstGeneratorTests {
    @Test func test_generate_producesTheRequestedBurstCount() {
        let result = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 3)

        #expect(result.bursts.count == 3)
    }

    @Test func test_generate_burstsAreInOrderAndNonOverlapping() {
        let result = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 4)

        for (earlier, later) in zip(result.bursts, result.bursts.dropFirst()) {
            #expect(earlier.range.endSample <= later.range.startSample)
        }
    }

    @Test func test_generate_eachBurstRangeFallsWithinTheSampleArray() {
        let result = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 2)

        for burst in result.bursts {
            #expect(burst.range.startSample >= 0)
            #expect(burst.range.endSample <= Int64(result.samples.count))
        }
    }

    @Test func test_generate_isDeterministic_sameParametersProduceIdenticalOutput() {
        let first = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 5)
        let second = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 5)

        #expect(first.samples == second.samples)
        #expect(first.bursts == second.bursts)
    }

    @Test func test_generate_burstSamples_areNotSilent() {
        let result = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 1, burstDuration: 0.1)

        let burst = result.bursts[0]
        let burstSamples = result.samples[Int(burst.range.startSample)..<Int(burst.range.endSample)]
        #expect(burstSamples.contains { abs($0) > 0.01 })
    }

    @Test func test_generate_zeroBursts_producesOnlyLeadingSilence() {
        let result = GoldenToneBurstGenerator.generate(sampleRate: 16000, burstCount: 0)

        #expect(result.bursts.isEmpty)
        #expect(result.samples.isEmpty)
    }
}
