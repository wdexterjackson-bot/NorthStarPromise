/// Why an `AVAudioSession` interruption began (docs/02 §2, `.interruptionBegan`).
public enum InterruptionCause: String, Sendable, Hashable, Codable, CaseIterable {
    case phoneCall
    case siri
    case otherApp
    case systemAlert
}

/// A coarse audio route endpoint, for `.routeChange` events. Deliberately not
/// the full `AVAudioSession.Port` vocabulary — just enough to explain a gap.
public enum AudioRouteEndpoint: String, Sendable, Hashable, Codable, CaseIterable {
    case builtInMic
    case bluetooth
    case airpods
    case wiredHeadset
    case other
}

/// A user- or system-marked moment (docs/02 §2, `.marker`).
public enum MarkerKind: String, Sendable, Hashable, Codable, CaseIterable {
    case important
    case actionItem
    case question
}

/// A non-stopping capture health signal (docs/02 §2, `.levelWarning`; NSP-060).
public enum LevelWarningKind: String, Sendable, Hashable, Codable, CaseIterable {
    case silence
    case clipping
    case inputLoss
    case lowLevel
}

/// Mirrors `ProcessInfo.ThermalState` without importing Foundation's
/// platform-specific type into the timeline payload (docs/02 §2, `.thermal`).
public enum ThermalState: String, Sendable, Hashable, Codable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical
}

/// Why capture was force-stopped with a sealed, playable manifest
/// (docs/02 §2, `.sealedStop`; NSP-059).
public enum SealedStopReason: String, Sendable, Hashable, Codable, CaseIterable {
    case thermalCritical
    case batteryCritical
    case storageCritical
}

/// One append-only timeline entry (docs/02 §2, `TimelineEvent.type`). Ordered
/// by `TimelineEvent.sampleOffset`, never by `wallClock`.
public enum TimelineEventType: Sendable, Hashable, Codable {
    case start
    case pause
    case resume
    case interruptionBegan(cause: InterruptionCause)
    case interruptionEnded
    case routeChange(from: AudioRouteEndpoint, to: AudioRouteEndpoint)
    case marker(kind: MarkerKind)
    case levelWarning(kind: LevelWarningKind)
    case thermal(state: ThermalState)
    case batteryWarning
    case storageWarning
    case sealedStop(reason: SealedStopReason)
    case stop
}
