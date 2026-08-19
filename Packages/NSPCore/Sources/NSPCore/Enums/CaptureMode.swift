/// How a meeting's audio entered the system (docs/02 §2, `Meeting.captureMode`).
public enum CaptureMode: String, Sendable, Hashable, Codable, CaseIterable {
    case watch
    case phone
    case pad
    case `import`
    case onlineAssistant
    case dialer
}
