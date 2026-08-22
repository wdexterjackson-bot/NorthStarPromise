import ActivityKit
import Foundation

/// The cross-target contract between `NorthStarPhone` (which starts,
/// updates, and ends the Activity as `RecordingSession`/`AmbientCoordinator`
/// state changes — see `App/Phone/CaptureActivityController.swift`) and
/// `NorthStarWidgets` (which only renders it). Lives outside both targets'
/// own source folders so neither has to import the other — the same reason
/// `docs/03-CAPTURE-AND-TRANSFER.md` §2.2 states the rule this type exists
/// to satisfy: "the Live Activity is a *view* of capture state and never a
/// source of truth."
public struct CaptureActivityAttributes: ActivityAttributes {
    public enum Mode: String, Codable, Hashable, Sendable {
        case meeting
        case mentalNote
        case exerciseMode

        public var label: String {
            switch self {
            case .meeting: "Meeting"
            case .mentalNote: "Mental Note"
            case .exerciseMode: "Exercise Mode"
            }
        }

        public var symbolName: String {
            switch self {
            case .meeting: "mic.fill"
            case .mentalNote: "brain.head.profile"
            case .exerciseMode: "ear"
            }
        }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var mode: Mode
        /// The moment capture began (or, across a pause/resume, when the
        /// *current* running span began) — lets the widget render a live-
        /// ticking `Text(timerInterval:)` without `NorthStarPhone` waking up
        /// to push per-second updates.
        public var startedAt: Date
        public var isPaused: Bool

        public init(mode: Mode, startedAt: Date, isPaused: Bool = false) {
            self.mode = mode
            self.startedAt = startedAt
            self.isPaused = isPaused
        }
    }

    public init() {}
}
