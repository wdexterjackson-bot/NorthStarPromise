#if DEBUG
    import Foundation
    import NSPCore

    /// Dev-only sample data so Today/Library have something real to show
    /// while screens that create their own content (recording, note-taking,
    /// processing) are still being built out. `#if DEBUG`-gated — never
    /// compiled into a release build, never confusable with real user data.
    ///
    /// Deliberately doesn't reuse `NSPTestSupport`'s `MeetingFixtureBuilder`:
    /// `NSPTestSupport` is a test-only package and must never link into the
    /// shipping app target, debug configuration or not (the same boundary
    /// this project already draws around `NSPTestSupport` elsewhere — see
    /// `ArchitectureTests.swift`'s I5 allow-list comment).
    enum DebugFixtures {
        @MainActor
        static func seedIfNeeded(environment: AppEnvironment) async {
            guard let policy = environment.defaultPolicy else { return }
            let hasSeededKey = "com.dexterjackson.northstarpromise.debugFixturesSeeded"
            guard !UserDefaults.standard.bool(forKey: hasSeededKey) else { return }

            let now = environment.clock.now()
            let samples: [Meeting] = [
                Meeting(
                    meetingID: MeetingID(rawValue: UUID()), workspaceID: policy.workspaceID,
                    title: "Weekly product sync", captureMode: .phone, originDeviceID: environment.deviceID,
                    startedAt: now.addingTimeInterval(-3600 * 26), endedAt: now.addingTimeInterval(-3600 * 26 + 1800),
                    canonicalDuration: SampleDuration(sampleCount: 48000 * 1800, sampleRate: 48000),
                    lifecycleState: .readyForReview, policyID: policy.policyID,
                    processingMode: policy.defaultProcessingMode, availability: .complete,
                    createdAt: now.addingTimeInterval(-3600 * 26), updatedAt: now.addingTimeInterval(-3600 * 26)),
                Meeting(
                    meetingID: MeetingID(rawValue: UUID()), workspaceID: policy.workspaceID,
                    title: "1:1 with Priya", captureMode: .phone, originDeviceID: environment.deviceID,
                    startedAt: now.addingTimeInterval(-3600 * 50), endedAt: now.addingTimeInterval(-3600 * 50 + 900),
                    canonicalDuration: SampleDuration(sampleCount: 48000 * 900, sampleRate: 48000),
                    lifecycleState: .savedRaw, policyID: policy.policyID, processingMode: policy.defaultProcessingMode,
                    availability: .complete, createdAt: now.addingTimeInterval(-3600 * 50),
                    updatedAt: now.addingTimeInterval(-3600 * 50)),
                Meeting(
                    meetingID: MeetingID(rawValue: UUID()), workspaceID: policy.workspaceID,
                    title: "Design review — imported clip", captureMode: .import, originDeviceID: environment.deviceID,
                    startedAt: now.addingTimeInterval(-3600 * 3), endedAt: now.addingTimeInterval(-3600 * 3 + 2400),
                    canonicalDuration: SampleDuration(sampleCount: 48000 * 2400, sampleRate: 48000),
                    lifecycleState: .processing, policyID: policy.policyID,
                    processingMode: policy.defaultProcessingMode,
                    availability: .complete, createdAt: now.addingTimeInterval(-3600 * 3),
                    updatedAt: now.addingTimeInterval(-3600 * 3)),
            ]

            for meeting in samples {
                try? await environment.meetingRepository.insert(meeting, at: meeting.createdAt)
            }
            UserDefaults.standard.set(true, forKey: hasSeededKey)
        }
    }
#endif
