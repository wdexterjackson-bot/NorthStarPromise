import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner + Dynamic Island presentation for an active capture
/// session — Voice Memos' own Lock Screen recording indicator is the
/// reference point (2026-08-22 request). Read-only: tapping it opens
/// `NorthStarPhone`, same as any other Live Activity without its own
/// interactive button; Stop-from-the-Lock-Screen is a follow-up, not
/// something this pass builds (see `CaptureActivityController`'s own doc
/// comment).
struct CaptureLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CaptureActivityAttributes.self) { context in
            CaptureLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.mode.symbolName)
                        .foregroundStyle(.red)
                        .font(.system(size: 18, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CaptureTimerText(state: context.state, fontSize: 15)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.mode.label)
                        .font(.system(size: 14, weight: .semibold))
                }
            } compactLeading: {
                Image(systemName: context.state.mode.symbolName)
                    .foregroundStyle(.red)
            } compactTrailing: {
                CaptureTimerText(state: context.state, fontSize: 13)
                    .frame(width: 46)
            } minimal: {
                Image(systemName: context.state.mode.symbolName)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct CaptureLockScreenView: View {
    let state: CaptureActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.red).frame(width: 44, height: 44)
                Image(systemName: state.mode.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isPaused ? "\(state.mode.label) — Paused" : "Recording · \(state.mode.label)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                CaptureTimerText(state: state, fontSize: 13)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// A live-ticking elapsed-time label that needs no app-process wakeups —
/// `Text(timerInterval:)` renders and advances entirely within
/// SpringBoard/the Lock Screen's own render pass. Frozen (not ticking)
/// while paused, since a paused session isn't actually elapsing.
private struct CaptureTimerText: View {
    let state: CaptureActivityAttributes.ContentState
    let fontSize: CGFloat

    var body: some View {
        if state.isPaused {
            Text("Paused")
                .font(.system(size: fontSize, weight: .medium))
        } else {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .font(.system(size: fontSize, weight: .medium))
                .monospacedDigit()
        }
    }
}
