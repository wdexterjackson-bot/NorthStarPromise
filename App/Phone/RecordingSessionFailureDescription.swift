import NSPMedia

/// Split out of `RecordingSession` itself only to keep that type under the
/// project's type-body-length budget — pure string formatting, no access to
/// any of the session's own state.
extension RecordingSession {
    static func describeFailure(_ error: Error) -> String {
        if let captureError = error as? CaptureEngineError {
            switch captureError {
            case .alreadyCapturing: return "Already recording."
            case .notCapturing: return "Not currently recording."
            case .backendFailure(let reason):
                if reason.contains("permissionDenied") {
                    return "Microphone access is off. Turn it on in Settings \u{203A} Privacy \u{203A} Microphone."
                }
                return "Couldn't access the microphone: \(reason)"
            }
        }
        return "\(error)"
    }
}
