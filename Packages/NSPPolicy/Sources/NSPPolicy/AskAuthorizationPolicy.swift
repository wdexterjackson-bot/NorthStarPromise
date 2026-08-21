import NSPCore

/// The pure eligibility rule behind Ask's "authorization before retrieval"
/// hard requirement (docs/04 §10.2, docs/06 §5, docs/02 §5, threat-model row
/// T4): a meeting is eligible for retrieval only if it isn't excluded from
/// memory, isn't (soft-)deleted, and — for `.localOnly` meetings — actually
/// originated on this device. No I/O here, matching `PolicyAuthority`'s own
/// shape; the DB-touching half (`AskScope` → a concrete `Set<MeetingID>`)
/// lives in `NSPIntelligence`'s `AskAuthorizationResolver`, which is the
/// lowest package that can see both this policy and `MeetingRepository`.
///
/// The `.localOnly`/`originDeviceID` check here is defense-in-depth rather
/// than a rule expected to ever actually fire: `.localOnly` means zero bytes
/// leave the device, including metadata (docs/02 §5), so a `.localOnly`
/// meeting from another device structurally can never sync into this
/// device's local DB in the first place — it just never gets the chance to
/// reach this predicate. Kept explicit anyway because it's cheap, correct,
/// and matches the docs' literal wording.
public enum AskAuthorizationPolicy {
    public static func isEligible(meeting: Meeting, currentDeviceID: DeviceID) -> Bool {
        !meeting.excludedFromMemory && meeting.deletedAt == nil
            && (meeting.processingMode != .localOnly || meeting.originDeviceID == currentDeviceID)
    }
}
