import Foundation
import NSPCore

/// Where one contributing device's local sample counter sits relative to
/// wall-clock time (docs/03 §4: "Each contributing device has a
/// `DeviceAnchor`"). `sampleZeroWallClock` is the one deliberate use of
/// wall clock in the whole reconciliation path — it's how two independent
/// per-device sample counters get related at all before any audio-based
/// refinement is possible.
public struct DeviceAnchor: Sendable, Hashable {
    public let deviceID: DeviceID
    public let sampleZeroWallClock: Date
    public let sampleRate: Int

    public init(deviceID: DeviceID, sampleZeroWallClock: Date, sampleRate: Int) {
        self.deviceID = deviceID
        self.sampleZeroWallClock = sampleZeroWallClock
        self.sampleRate = sampleRate
    }
}
