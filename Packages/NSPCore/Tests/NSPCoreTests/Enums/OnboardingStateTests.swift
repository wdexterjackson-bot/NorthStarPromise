import Testing

@testable import NSPCore

/// "The First Hour" wizard's own state machine (2026-08-22) — only
/// `.notStarted` auto-presents, and only `.inProgress` resumes an existing
/// session rather than restarting from step 0 (`OnboardingState`'s own doc
/// comment explains why `.skipped` and `.completed` both restart).
@Suite("OnboardingState")
struct OnboardingStateTests {
    @Test func test_shouldAutoPresent_isTrueOnlyForNotStarted() {
        #expect(OnboardingState.notStarted.shouldAutoPresent == true)
        #expect(OnboardingState.inProgress.shouldAutoPresent == false)
        #expect(OnboardingState.skipped.shouldAutoPresent == false)
        #expect(OnboardingState.completed.shouldAutoPresent == false)
    }

    @Test func test_resumesExistingSession_isTrueOnlyForInProgress() {
        #expect(OnboardingState.notStarted.resumesExistingSession == false)
        #expect(OnboardingState.inProgress.resumesExistingSession == true)
        #expect(OnboardingState.skipped.resumesExistingSession == false)
        #expect(OnboardingState.completed.resumesExistingSession == false)
    }

    @Test func test_rawValue_roundTripsForEveryCase() {
        for state in OnboardingState.allCases {
            #expect(OnboardingState(rawValue: state.rawValue) == state)
        }
    }
}
