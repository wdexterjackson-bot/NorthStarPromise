import Foundation
import NSPCore

/// Builds a self-consistent `Meeting` fixture with sensible defaults,
/// overridable field by field. IDs and timestamps come from the supplied
/// `Clock` so a whole test's fixtures share one deterministic time base
/// (docs/01 §3, "NSPTestSupport... fixture meeting builder").
public struct MeetingFixtureBuilder {
    private var workspaceID: WorkspaceID
    private var title: String = "Weekly sync"
    private var captureMode: CaptureMode = .watch
    private var originDeviceID: DeviceID
    private var lifecycleState: MeetingState = .readyForReview
    private var processingMode: ProcessingMode = .localOnly
    private var availability: Availability = .complete
    private var canonicalDuration: SampleDuration = SampleDuration(sampleCount: 1_800_000, sampleRate: 16000)

    private let clock: Clock

    public init(clock: Clock = FakeClock()) {
        self.clock = clock
        self.workspaceID = WorkspaceID.generate(clock: clock)
        self.originDeviceID = DeviceID.generate(clock: clock)
    }

    public func withTitle(_ title: String) -> MeetingFixtureBuilder {
        var copy = self
        copy.title = title
        return copy
    }

    public func withCaptureMode(_ mode: CaptureMode) -> MeetingFixtureBuilder {
        var copy = self
        copy.captureMode = mode
        return copy
    }

    public func withLifecycleState(_ state: MeetingState) -> MeetingFixtureBuilder {
        var copy = self
        copy.lifecycleState = state
        return copy
    }

    public func withProcessingMode(_ mode: ProcessingMode) -> MeetingFixtureBuilder {
        var copy = self
        copy.processingMode = mode
        return copy
    }

    public func withAvailability(_ availability: Availability) -> MeetingFixtureBuilder {
        var copy = self
        copy.availability = availability
        return copy
    }

    public func withCanonicalDuration(_ duration: SampleDuration) -> MeetingFixtureBuilder {
        var copy = self
        copy.canonicalDuration = duration
        return copy
    }

    public func build() -> Meeting {
        let now = clock.now()
        return Meeting(
            meetingID: .generate(clock: clock),
            workspaceID: workspaceID,
            title: title,
            captureMode: captureMode,
            originDeviceID: originDeviceID,
            startedAt: now,
            endedAt: now.addingTimeInterval(canonicalDuration.seconds),
            canonicalDuration: canonicalDuration,
            lifecycleState: lifecycleState,
            policyID: .generate(clock: clock),
            processingMode: processingMode,
            availability: availability,
            createdAt: now,
            updatedAt: now
        )
    }
}
