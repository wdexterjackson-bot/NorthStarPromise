import Foundation

/// One attempt (and, on retry, re-attempt) to write to an external system
/// through the integration outbox — idempotent by `idempotencyKey`, and every
/// retry is recorded here rather than silently re-sent (docs/02 §2,
/// Invariant I6).
public struct IntegrationReceipt: Sendable, Hashable, Codable, Identifiable {
    public let integrationReceiptID: IntegrationReceiptID
    public var id: IntegrationReceiptID { integrationReceiptID }

    public let destination: String
    public var externalID: String?
    public let idempotencyKey: String
    public let requestHash: String
    public var response: IntegrationResponse?
    public var retryHistory: [IntegrationRetry]

    public init(
        integrationReceiptID: IntegrationReceiptID,
        destination: String,
        externalID: String? = nil,
        idempotencyKey: String,
        requestHash: String,
        response: IntegrationResponse? = nil,
        retryHistory: [IntegrationRetry] = []
    ) {
        self.integrationReceiptID = integrationReceiptID
        self.destination = destination
        self.externalID = externalID
        self.idempotencyKey = idempotencyKey
        self.requestHash = requestHash
        self.response = response
        self.retryHistory = retryHistory
    }
}

public struct IntegrationResponse: Sendable, Hashable, Codable {
    public let succeeded: Bool
    public let statusDescription: String
    public let receivedAt: Date

    public init(succeeded: Bool, statusDescription: String, receivedAt: Date) {
        self.succeeded = succeeded
        self.statusDescription = statusDescription
        self.receivedAt = receivedAt
    }
}

public struct IntegrationRetry: Sendable, Hashable, Codable {
    public let attemptedAt: Date
    public let outcome: IntegrationResponse

    public init(attemptedAt: Date, outcome: IntegrationResponse) {
        self.attemptedAt = attemptedAt
        self.outcome = outcome
    }
}
