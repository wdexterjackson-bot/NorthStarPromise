import Foundation
import NSPCore
import Testing

@testable import NSPPolicy

@Suite("PolicyAuthority")
struct PolicyAuthorityTests {
    private static func makeWorkspaceDefault(
        mode: ProcessingMode = .cloudAllowed, blockedDomains: [String] = ["a.example"]
    ) -> Policy {
        Policy(
            policyID: PolicyID(rawValue: UUID()),
            workspaceID: WorkspaceID(rawValue: UUID()),
            retentionDays: 90,
            defaultProcessingMode: mode,
            announcementRequired: true,
            blockedDomains: blockedDomains,
            blockedLocations: ["hq"]
        )
    }

    @Test func test_freezeSnapshot_copiesEveryFieldUnderANewPolicyID() {
        let workspaceDefault = Self.makeWorkspaceDefault()
        let newPolicyID = PolicyID(rawValue: UUID())

        let snapshot = PolicyAuthority.freezeSnapshot(from: workspaceDefault, newPolicyID: newPolicyID)

        #expect(snapshot.policyID == newPolicyID)
        #expect(snapshot.policyID != workspaceDefault.policyID)
        #expect(snapshot.workspaceID == workspaceDefault.workspaceID)
        #expect(snapshot.retentionDays == workspaceDefault.retentionDays)
        #expect(snapshot.defaultProcessingMode == workspaceDefault.defaultProcessingMode)
        #expect(snapshot.announcementRequired == workspaceDefault.announcementRequired)
        #expect(snapshot.blockedDomains == workspaceDefault.blockedDomains)
        #expect(snapshot.blockedLocations == workspaceDefault.blockedLocations)
    }

    @Test func test_laterEditsToTheWorkspaceDefault_neverAffectAnAlreadyFrozenSnapshot() {
        var workspaceDefault = Self.makeWorkspaceDefault(mode: .localOnly)
        let snapshot = PolicyAuthority.freezeSnapshot(
            from: workspaceDefault, newPolicyID: PolicyID(rawValue: UUID()))

        // The workspace admin loosens the *default* after this meeting armed.
        workspaceDefault.defaultProcessingMode = .cloudAllowed

        #expect(snapshot.defaultProcessingMode == .localOnly)
    }

    @Test func test_tighteningAndNoOp_areAlwaysAccepted() throws {
        for mode in ProcessingMode.allCases {
            let snapshot = PolicyAuthority.freezeSnapshot(
                from: Self.makeWorkspaceDefault(mode: mode), newPolicyID: PolicyID(rawValue: UUID()))
            let result = try PolicyAuthority.requestModeChange(on: snapshot, to: mode)
            #expect(result.defaultProcessingMode == mode)
        }

        let cloudSnapshot = PolicyAuthority.freezeSnapshot(
            from: Self.makeWorkspaceDefault(mode: .cloudAllowed), newPolicyID: PolicyID(rawValue: UUID()))
        #expect(
            try PolicyAuthority.requestModeChange(on: cloudSnapshot, to: .onDevicePreferred).defaultProcessingMode
                == .onDevicePreferred)
        #expect(
            try PolicyAuthority.requestModeChange(on: cloudSnapshot, to: .localOnly).defaultProcessingMode == .localOnly
        )

        let onDeviceSnapshot = PolicyAuthority.freezeSnapshot(
            from: Self.makeWorkspaceDefault(mode: .onDevicePreferred), newPolicyID: PolicyID(rawValue: UUID()))
        #expect(
            try PolicyAuthority.requestModeChange(on: onDeviceSnapshot, to: .localOnly).defaultProcessingMode
                == .localOnly)
    }

    @Test func test_loosening_isRejectedForEveryDirection() {
        let localOnlySnapshot = PolicyAuthority.freezeSnapshot(
            from: Self.makeWorkspaceDefault(mode: .localOnly), newPolicyID: PolicyID(rawValue: UUID()))
        #expect(throws: PolicyError.self) {
            try PolicyAuthority.requestModeChange(on: localOnlySnapshot, to: .onDevicePreferred)
        }
        #expect(throws: PolicyError.self) {
            try PolicyAuthority.requestModeChange(on: localOnlySnapshot, to: .cloudAllowed)
        }

        let onDeviceSnapshot = PolicyAuthority.freezeSnapshot(
            from: Self.makeWorkspaceDefault(mode: .onDevicePreferred), newPolicyID: PolicyID(rawValue: UUID()))
        #expect(throws: PolicyError.self) {
            try PolicyAuthority.requestModeChange(on: onDeviceSnapshot, to: .cloudAllowed)
        }
    }

    /// Exhaustively fuzzes every (from, to) pair over all three modes —
    /// NSP-015 acceptance: "mode cannot be mutated after Arming by any API
    /// path." Independently restates the legal-transition set so this test
    /// can't be tautological with `PolicyAuthority`'s own implementation.
    @Test func test_everyModePair_matchesTheIndependentlyStatedLegalTransitionSet() {
        let legalTransitions: Set<[ProcessingMode]> = [
            [.localOnly, .localOnly],
            [.onDevicePreferred, .onDevicePreferred], [.onDevicePreferred, .localOnly],
            [.cloudAllowed, .cloudAllowed], [.cloudAllowed, .onDevicePreferred], [.cloudAllowed, .localOnly],
        ]

        for from in ProcessingMode.allCases {
            for to in ProcessingMode.allCases {
                let snapshot = PolicyAuthority.freezeSnapshot(
                    from: Self.makeWorkspaceDefault(mode: from), newPolicyID: PolicyID(rawValue: UUID()))
                let shouldSucceed = legalTransitions.contains([from, to])

                if shouldSucceed {
                    #expect(throws: Never.self) {
                        try PolicyAuthority.requestModeChange(on: snapshot, to: to)
                    }
                } else {
                    #expect(throws: PolicyError.self) {
                        try PolicyAuthority.requestModeChange(on: snapshot, to: to)
                    }
                }
            }
        }
    }
}
