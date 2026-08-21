import CloudKit
import NSPCore
import NSPPersistence

/// The incremental change-token fetch loop (docs/02 §6, NSP-036): pages
/// through `CloudKitGateway.fetchChanges` until `moreComing` is `false`,
/// upserts every decoded `CD_Meeting`/`CD_Segment` record into local
/// storage, and recomputes `Availability` for every meeting touched —
/// "Meeting opens as `.partial` listing the exact missing segments and the
/// device that last held them" is `MeetingAvailabilityReconciler`'s job;
/// this type only owns getting fresh rows into storage for it to read.
///
/// Record types other than `CD_Meeting`/`CD_Segment` (transcript turns,
/// notes, insights...) are ignored here — each of those lands its own
/// sync path in a later ticket.
public actor ZoneSyncEngine {
    private let gateway: any CloudKitGateway
    private let tokenStore: any ChangeTokenStore
    private let meetingRepository: any MeetingRepository
    private let segmentRepository: any SegmentRepository
    private let clock: any Clock

    public init(
        gateway: some CloudKitGateway, tokenStore: some ChangeTokenStore, meetingRepository: some MeetingRepository,
        segmentRepository: some SegmentRepository, clock: some Clock = SystemClock()
    ) {
        self.gateway = gateway
        self.tokenStore = tokenStore
        self.meetingRepository = meetingRepository
        self.segmentRepository = segmentRepository
        self.clock = clock
    }

    /// Returns every `MeetingID` whose local `Availability` may have
    /// changed as a result of this sync pass.
    @discardableResult
    public func syncZone(_ zoneID: CKRecordZone.ID) async throws -> Set<MeetingID> {
        var touchedMeetingIDs: Set<MeetingID> = []
        var currentCursor = await tokenStore.cursor(for: zoneID)

        while true {
            let page = try await gateway.fetchChanges(in: zoneID, since: currentCursor)

            for record in page.changedRecords {
                switch record.recordType {
                case CloudKitRecordType.meeting:
                    let meeting = try CloudKitRecordMapper.meeting(from: record)
                    try await upsertMeeting(meeting)
                    touchedMeetingIDs.insert(meeting.meetingID)
                case CloudKitRecordType.segment:
                    let segment = try CloudKitRecordMapper.segment(from: record)
                    try await upsertSegment(segment)
                    // `Note`/`BrainDump` segments have no sync scaffolding
                    // yet (`CloudKitRecordMapper`'s own doc comment) — only
                    // a meeting-owned segment feeds availability recompute.
                    if case .meeting(let meetingID) = segment.owner {
                        touchedMeetingIDs.insert(meetingID)
                    }
                default:
                    continue
                }
            }

            currentCursor = page.cursor
            await tokenStore.setCursor(currentCursor, for: zoneID)

            guard page.moreComing else { break }
        }

        for meetingID in touchedMeetingIDs {
            try await recomputeAvailability(for: meetingID)
        }

        return touchedMeetingIDs
    }

    private func upsertMeeting(_ meeting: Meeting) async throws {
        if try await meetingRepository.find(meeting.meetingID) != nil {
            try await meetingRepository.update(meeting, at: clock.now())
        } else {
            try await meetingRepository.insert(meeting, at: clock.now())
        }
    }

    private func upsertSegment(_ segment: Segment) async throws {
        if try await segmentRepository.find(segment.segmentID) != nil {
            try await segmentRepository.update(segment, at: clock.now())
        } else {
            try await segmentRepository.insert(segment, at: clock.now())
        }
    }

    private func recomputeAvailability(for meetingID: MeetingID) async throws {
        guard var meeting = try await meetingRepository.find(meetingID) else { return }
        let segments = try await segmentRepository.fetchAll(owner: .meeting(meetingID))
        meeting.availability = MeetingAvailabilityReconciler.availability(for: segments)
        try await meetingRepository.update(meeting, at: clock.now())
    }
}
