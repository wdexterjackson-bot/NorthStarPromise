import AVFoundation
import Foundation
import Observation
import WatchKit

/// NSP-002 measurement tool only. Not `NSPMedia` — the production `CaptureEngine` actor lands at
/// NSP-018/NSP-019 once this spike's results lock a recording-affordance strategy. Delete this
/// whole `Spike/` folder once `docs/reports/hardware-<date>.md` is filled in and NSP-010 lands.
enum SpikeStrategy: String, CaseIterable, Identifiable {
    case plainSession = "A — plain record session"
    case extendedRuntime = "B — extended runtime session"
    case audioRecordingIntent = "C — AudioRecordingIntent"

    var id: String { rawValue }
}

@Observable
final class SpikeRecordingController: NSObject {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var logLines: [String] = []

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt: Date?
    private var extendedSession: WKExtendedRuntimeSession?

    override init() {
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
    }

    func start(strategy: SpikeStrategy) {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            appendLog("FAIL session activation: \(error)")
            return
        }

        let fileURL = Self.newRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            guard recorder.record() else {
                appendLog("FAIL recorder.record() returned false")
                return
            }
            self.recorder = recorder
        } catch {
            appendLog("FAIL recorder init: \(error)")
            return
        }

        switch strategy {
        case .plainSession:
            break

        case .extendedRuntime:
            let extended = WKExtendedRuntimeSession()
            extended.delegate = self
            extended.start()
            extendedSession = extended

        case .audioRecordingIntent:
            // The dedicated `AudioRecordingIntent` App Intents protocol (docs/03 §2.2) needs its
            // exact conformance shape verified against the SDK installed on the test machine —
            // it is a spike input, not something to guess at here. Explore it directly in Xcode
            // (new file → App Intent → check availability/protocol requirements) alongside this
            // harness, and note what you find in the report's strategy-C row.
            appendLog("NOTE strategy C: verify AudioRecordingIntent's shape directly in Xcode before trusting this run")
        }

        startedAt = Date()
        isRecording = true
        appendLog("START strategy=\(strategy.rawValue) file=\(fileURL.lastPathComponent)")

        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        guard isRecording else { return }

        recorder?.stop()
        recorder = nil
        extendedSession?.invalidate()
        extendedSession = nil
        timer?.invalidate()
        timer = nil
        isRecording = false

        appendLog("STOP elapsed=\(Int(elapsed))s")
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        let battery = WKInterfaceDevice.current().batteryLevel
        let thermal = ProcessInfo.processInfo.thermalState.rawValue
        appendLog("TICK elapsed=\(Int(elapsed))s battery=\(battery) thermal=\(thermal)")
    }

    private func appendLog(_ line: String) {
        logLines.append("\(ISO8601DateFormatter().string(from: Date())) \(line)")
    }

    var exportText: String {
        logLines.joined(separator: "\n")
    }

    private static func newRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spike-\(Int(Date().timeIntervalSince1970)).m4a")
    }
}

extension SpikeRecordingController: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        appendLog("EXTENDED_SESSION invalidated reason=\(reason.rawValue) error=\(String(describing: error))")
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        appendLog("EXTENDED_SESSION started")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        appendLog("EXTENDED_SESSION willExpire")
    }
}
