import Foundation
import NSPCore
import NSPPersistence

/// In-memory `PolicyRepository` so tests never touch a real database
/// (docs/11 §4, NSP-015).
public actor FakePolicyRepository: PolicyRepository {
    private var storage: [PolicyID: Policy] = [:]

    public init() {}

    public func insert(_ policy: Policy, at date: Date) async throws {
        storage[policy.policyID] = policy
    }

    public func update(_ policy: Policy, at date: Date) async throws {
        guard storage[policy.policyID] != nil else {
            throw PersistenceError.notFound(table: "policy", key: policy.policyID.description)
        }
        storage[policy.policyID] = policy
    }

    public func find(_ id: PolicyID) async throws -> Policy? {
        storage[id]
    }
}
