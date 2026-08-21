import NSPCore
import NSPDesignSystem
import SwiftUI

/// One ruled line's state: its text, the `NoteBlock` it's backed by (once
/// it has one), and the margin label to display.
struct PadNoteLine: Identifiable {
    let id = UUID()
    var text: String = ""
    var block: NoteBlock?
    var timestampLabel: String?
}

struct PadNoteLineRow: View {
    @Binding var line: PadNoteLine
    var focusedLineID: FocusState<UUID?>.Binding

    /// The timestamp gutter's width — shared with `PadRecordingCanvas`'s
    /// margin rule so the two can never drift out of sync with each other
    /// (docs/07 §5's red rule belongs immediately right of the gutter, not
    /// cutting through the timestamp text itself).
    static let timestampGutterWidth: CGFloat = 52
    /// One ruled line's height — shared with `PadRecordingCanvas`'s ruled
    /// background so a single-line entry lands exactly on a rule, the way
    /// real ruled paper does. It's a *minimum*, not a fixed height: a long
    /// entry that wraps to several visual lines grows past it (bottom-
    /// aligned, so the short common case still sits precisely on its rule —
    /// only entries that actually need more room take it). A blank ruled
    /// line has no `PadNoteLineRow` at all (the background covers the whole
    /// page on its own), so this only needs to be correct for rows that do
    /// exist.
    static let rowHeight: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NSPSpacing.medium) {
            Text(line.timestampLabel ?? "--:--")
                .font(Typo.ui(11.5, .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
                .frame(width: Self.timestampGutterWidth, alignment: .trailing)

            // `axis: .vertical` wraps long notes onto additional visual
            // lines instead of scrolling the field horizontally — Return
            // still submits (`.onSubmit` in `PadRecordingCanvas` moves to
            // the next ruled line), it doesn't insert a line break here.
            TextField("", text: $line.text, axis: .vertical)
                .font(Typo.ui(14, .medium))
                .focused(focusedLineID, equals: line.id)
        }
        .frame(minHeight: Self.rowHeight, alignment: .bottom)
    }
}
