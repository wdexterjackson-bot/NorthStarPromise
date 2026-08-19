import Testing

import NSPCore

@testable import NSPTestSupport

@Suite("FakeFeatureFlagProvider")
struct FakeFeatureFlagProviderTests {
    @Test func test_defaultProvider_hasNoFlagsEnabled() {
        let provider = FakeFeatureFlagProvider()

        for flag in FeatureFlag.allCases {
            #expect(!provider.isEnabled(flag))
        }
    }

    @Test func test_enabledSet_onlyThoseFlagsReportEnabled() {
        let provider = FakeFeatureFlagProvider(enabled: [.iPadPencilCanvas])

        #expect(provider.isEnabled(.iPadPencilCanvas))
        #expect(!provider.isEnabled(.cloudSummarization))
        #expect(!provider.isEnabled(.watchLiveTranscriptPreview))
    }
}
