import SwiftUI

/// The "voice thermometer": a segmented, multicolor input-level bar so a
/// recording user gets a continuous, glanceable signal that the mic is
/// actually picking something up — green for normal speech, climbing
/// through yellow and into red as input gets hot. Domain-agnostic (takes a
/// 0...1 level, not a `RecordingSession`), same reasoning as
/// `NSPStatusBadge`.
public struct NSPLevelMeter: View {
    /// 0 (silence) ... 1 (full scale).
    public let level: Float
    public var segmentCount: Int

    public init(level: Float, segmentCount: Int = 24) {
        self.level = level
        self.segmentCount = segmentCount
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Self.color(forSegment: index, of: segmentCount))
                    .opacity(isLit(index) ? 1 : 0.12)
            }
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.12), value: level)
        // The "Recording" status pill already carries this state for
        // VoiceOver; the meter itself is a purely visual pulse with
        // nothing distinct to announce per-frame.
        .accessibilityHidden(true)
    }

    private func isLit(_ index: Int) -> Bool {
        Float(index) / Float(segmentCount) < level
    }

    private static func color(forSegment index: Int, of count: Int) -> Color {
        let fraction = Float(index) / Float(count)
        if fraction < 0.55 { return .green }
        if fraction < 0.82 { return .yellow }
        return .red
    }
}

#Preview {
    VStack(spacing: NSPSpacing.large) {
        NSPLevelMeter(level: 0.15)
        NSPLevelMeter(level: 0.55)
        NSPLevelMeter(level: 0.9)
    }
    .padding()
}
