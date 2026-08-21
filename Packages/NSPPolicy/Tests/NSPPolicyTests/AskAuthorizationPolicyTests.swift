import Foundation
import NSPCore
import Testing

@testable import NSPPolicy

@Suite("AskAuthorizationPolicy")
struct AskAuthorizationPolicyTests {
    private static let thisDevice = DeviceID(rawValue: UUID())
    private static let otherDevice = DeviceID(rawValue: UUID())

    private static func makeMeeting(
        excludedFromMemory: Bool = false, deletedAt: Date? = nil, processingMode: ProcessingMode = .cloudAllowed,
        originDeviceID: DeviceID = thisDevice
    ) -> Meeting {
        Meeting(
            meetingID: MeetingID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()), title: "Test",
            captureMode: .phone, originDeviceID: originDeviceID, startedAt: Date(), lifecycleState: .ready,
            policyID: PolicyID(rawValue: UUID()), processingMode: processingMode, availability: .complete,
            excludedFromMemory: excludedFromMemory, createdAt: Date(), updatedAt: Date(), deletedAt: deletedAt)
    }

    @Test func test_ordinaryMeeting_isEligible() {
        let meeting = Self.makeMeeting()
        #expect(AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: Self.thisDevice))
    }

    @Test func test_excludedFromMemory_isNotEligible() {
        let meeting = Self.makeMeeting(excludedFromMemory: true)
        #expect(!AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: Self.thisDevice))
    }

    @Test func test_softDeleted_isNotEligible() {
        let meeting = Self.makeMeeting(deletedAt: Date())
        #expect(!AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: Self.thisDevice))
    }

    @Test func test_localOnlyOriginatingOnThisDevice_isEligible() {
        let meeting = Self.makeMeeting(processingMode: .localOnly, originDeviceID: Self.thisDevice)
        #expect(AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: Self.thisDevice))
    }

    @Test func test_localOnlyOriginatingOnAnotherDevice_isNotEligible() {
        let meeting = Self.makeMeeting(processingMode: .localOnly, originDeviceID: Self.otherDevice)
        #expect(!AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: Self.thisDevice))
    }

    @Test func test_nonLocalOnlyFromAnotherDevice_isStillEligible() {
        // Only .localOnly is device-pinned — cloud-synced meetings from
        // another device are legitimately visible here once synced.
        let meeting = Self.makeMeeting(processingMode: .cloudAllowed, originDeviceID: Self.otherDevice)
        #expect(AskAuthorizationPolicy.isEligible(meeting: meeting, currentDeviceID: Self.thisDevice))
    }
}
