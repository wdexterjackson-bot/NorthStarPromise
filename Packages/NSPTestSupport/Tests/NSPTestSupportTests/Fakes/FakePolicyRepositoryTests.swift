import Foundation
import NSPCore
import NSPPersistence
import Testing

@testable import NSPTestSupport

@Suite("FakePolicyRepository")
struct FakePolicyRepositoryTests {
    @Test func test_insertFindUpdate() async throws {
        let repository = FakePolicyRepository()
        let policy = Policy(
            policyID: PolicyID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()),
            defaultProcessingMode: .cloudAllowed)

        try await repository.insert(policy, at: Date())
        #expect(try await repository.find(policy.policyID) == policy)

        var tightened = policy
        tightened.defaultProcessingMode = .localOnly
        try await repository.update(tightened, at: Date())
        #expect(try await repository.find(policy.policyID)?.defaultProcessingMode == .localOnly)
    }

    @Test func test_updateMissingPolicy_throws() async throws {
        let repository = FakePolicyRepository()
        let policy = Policy(
            policyID: PolicyID(rawValue: UUID()), workspaceID: WorkspaceID(rawValue: UUID()),
            defaultProcessingMode: .cloudAllowed)

        await #expect(throws: PersistenceError.self) {
            try await repository.update(policy, at: Date())
        }
    }
}
