import NSPDesignSystem
import SwiftUI

/// The Audio tab's waveform + trim strip — Voice Memos' "select a range,
/// drag the handles" gesture, over real per-bucket peaks
/// (`WaveformPeakExtractor`), not a decorative placeholder. Two draggable
/// handles bound `trimStartSeconds`/`trimEndSeconds`; the region outside
/// the selection dims so the kept range reads at a glance. Tapping the
/// track (not a handle) seeks there — a free, expected bonus of having a
/// real waveform on screen.
struct WaveformTrimView: View {
    let peaks: [Float]
    let durationSeconds: TimeInterval
    let currentTimeSeconds: TimeInterval
    @Binding var trimStartSeconds: TimeInterval
    @Binding var trimEndSeconds: TimeInterval
    let onSeek: (TimeInterval) -> Void

    private static let handleWidth: CGFloat = 14
    private static let trackHeight: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                waveformBars(width: width)
                dimOverlay(width: width)
                playhead(width: width)
                handle(atSeconds: trimStartSeconds, width: width, label: "Trim start") { newSeconds in
                    trimStartSeconds = min(max(0, newSeconds), trimEndSeconds - 0.2)
                }
                handle(atSeconds: trimEndSeconds, width: width, label: "Trim end") { newSeconds in
                    trimEndSeconds = max(min(durationSeconds, newSeconds), trimStartSeconds + 0.2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                onSeek(seconds(forX: location.x, width: width))
            }
        }
        .frame(height: Self.trackHeight)
    }

    private func waveformBars(width: CGFloat) -> some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let barWidth = size.width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let barHeight = max(2, CGFloat(peak) * size.height)
                let xOffset = CGFloat(index) * barWidth
                let rect = CGRect(
                    x: xOffset, y: (size.height - barHeight) / 2, width: max(1, barWidth - 1), height: barHeight)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Palette.accent.foreground))
            }
        }
        .frame(width: width)
    }

    private func dimOverlay(width: CGFloat) -> some View {
        let startX = xPosition(forSeconds: trimStartSeconds, width: width)
        let endX = xPosition(forSeconds: trimEndSeconds, width: width)
        return HStack(spacing: 0) {
            Rectangle().fill(Palette.canvas.opacity(0.72)).frame(width: max(0, startX))
            Rectangle().fill(Color.clear).frame(width: max(0, endX - startX))
            Rectangle().fill(Palette.canvas.opacity(0.72)).frame(width: max(0, width - endX))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func playhead(width: CGFloat) -> some View {
        if durationSeconds > 0 {
            Rectangle()
                .fill(Palette.record)
                .frame(width: 2, height: Self.trackHeight)
                .offset(x: xPosition(forSeconds: currentTimeSeconds, width: width) - 1)
                .allowsHitTesting(false)
        }
    }

    /// `DragGesture` alone leaves VoiceOver users with no way to move a
    /// handle at all, so this also exposes an adjustable action (1s per
    /// increment/decrement) — a real control, not just a labeled decoration.
    private func handle(
        atSeconds seconds: TimeInterval, width: CGFloat, label: String, onDrag: @escaping (TimeInterval) -> Void
    ) -> some View {
        Capsule()
            .fill(Palette.accent.foreground)
            .frame(width: 5, height: Self.trackHeight)
            .contentShape(Rectangle().size(width: Self.handleWidth, height: Self.trackHeight))
            .offset(x: xPosition(forSeconds: seconds, width: width) - 2.5)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onDrag(self.seconds(forX: value.location.x, width: width))
                }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Self.timeLabel(seconds))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onDrag(seconds + 1)
                case .decrement: onDrag(seconds - 1)
                default: break
                }
            }
    }

    private static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func xPosition(forSeconds seconds: TimeInterval, width: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        return CGFloat(seconds / durationSeconds) * width
    }

    private func seconds(forX xOffset: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        let fraction = max(0, min(1, xOffset / width))
        return fraction * durationSeconds
    }
}
