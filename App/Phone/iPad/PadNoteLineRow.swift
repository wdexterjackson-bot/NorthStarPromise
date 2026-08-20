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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NSPSpacing.medium) {
            Text(line.timestampLabel ?? "--:--")
                .font(.caption.monospacedDigit())
                .foregroundStyle(NSPColor.secondaryText)
                .frame(width: 52, alignment: .trailing)

            TextField("", text: $line.text)
                .font(.body)
                .focused(focusedLineID, equals: line.id)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.blue.opacity(0.25)).frame(height: 1)
        }
    }
}
