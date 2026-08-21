import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Notes tab: a real `NoteBlock` list backed by
/// `NoteBlockRepository` — add, edit, and delete all work end to end
/// against the database. AI proposing a merge into the recap (§ 7.3) isn't
/// built yet, so every block created here stays `.standalone`.
@MainActor
struct NotesTab: View {
    let meeting: Meeting
    let environment: AppEnvironment

    @State private var blocks: [NoteBlock] = []
    @State private var loadError: String?
    @State private var composerTarget: ComposerTarget?

    private enum ComposerTarget: Identifiable {
        case new
        case editing(NoteBlock)

        var id: String {
            switch self {
            case .new: return "new"
            case .editing(let block): return block.blockID.rawValue.uuidString
            }
        }
    }

    private var sortedBlocks: [NoteBlock] {
        blocks.sorted { $0.creationRange.startSample < $1.creationRange.startSample }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            HStack {
                Text("Notes").font(Typo.ui(15, .bold))
                Spacer()
                Button {
                    composerTarget = .new
                } label: {
                    Label("Add note", systemImage: "plus.circle.fill")
                }
                .disabled(environment.selfPersonID == nil)
            }

            if let loadError {
                Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            } else if blocks.isEmpty {
                ContentUnavailableView(
                    "No notes yet", systemImage: "note.text",
                    description: Text("Notes you take during or after this meeting appear here."))
            } else {
                VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                    ForEach(sortedBlocks) { block in
                        NoteBlockRowView(
                            block: block, onEdit: { composerTarget = .editing(block) },
                            onDelete: {
                                Task { await delete(block) }
                            })
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $composerTarget) { target in
            switch target {
            case .new:
                NoteComposerView(meeting: meeting, environment: environment, editing: nil, onSaved: apply)
            case .editing(let block):
                NoteComposerView(meeting: meeting, environment: environment, editing: block, onSaved: apply)
            }
        }
    }

    private func apply(_ block: NoteBlock) {
        if let index = blocks.firstIndex(where: { $0.blockID == block.blockID }) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
    }

    private func load() async {
        do {
            blocks = try await environment.noteBlockRepository.fetchAll(owner: .meeting(meeting.meetingID))
        } catch {
            loadError = "\(error)"
        }
    }

    private func delete(_ block: NoteBlock) async {
        do {
            try await environment.noteBlockRepository.delete(block.blockID)
            blocks.removeAll { $0.blockID == block.blockID }
        } catch {
            loadError = "\(error)"
        }
    }
}

/// One row: type + privacy indicator, a content preview, and an overflow
/// menu for edit/delete — a menu rather than `.swipeActions` since this
/// tab renders inside a `ScrollView`, not a `List` (`.swipeActions` only
/// works on list rows).
private struct NoteBlockRowView: View {
    let block: NoteBlock
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var previewText: String {
        switch block.content {
        case .text(let text): return text.isEmpty ? "(empty)" : text
        case .assetReference(let path): return "Attachment: \(path)"
        }
    }

    private var canEdit: Bool {
        if case .text = block.content { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: NSPSpacing.medium) {
            NSPIconBadge(symbolName: block.type.symbolName, tint: Palette.textSecondary, size: 26)

            VStack(alignment: .leading, spacing: NSPSpacing.extraSmall) {
                HStack(spacing: NSPSpacing.extraSmall) {
                    Text(block.type.displayName)
                        .font(Typo.ui(11.5, .bold))
                        .foregroundStyle(Palette.textTertiary)
                    if block.privacy == .privateToAuthor {
                        Image(systemName: "lock.fill")
                            .font(Typo.ui(10.5, .medium))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Text(previewText).font(Typo.ui(14, .medium))
            }

            Spacer(minLength: 0)

            Menu {
                if canEdit {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                }
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .nspCard()
        .contentShape(Rectangle())
        .onTapGesture { if canEdit { onEdit() } }
    }
}

/// Add/edit sheet. `NoteBlock.type` is immutable once created (docs/02 §2),
/// so editing never re-offers the type picker — only content and privacy
/// change on an existing block, recorded as a new `Operation` in its opLog.
private struct NoteComposerView: View {
    let meeting: Meeting
    let environment: AppEnvironment
    let editing: NoteBlock?
    let onSaved: (NoteBlock) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: NoteBlockType
    @State private var text: String
    @State private var isPrivate: Bool
    @State private var isSaving = false
    @State private var saveError: String?

    /// The subset of the thirteen `NoteBlockType` cases this text-only
    /// composer can create. `.sketch`/`.photo`/`.table`/`.code`/
    /// `.linkPreview`/`.file`/`.transcriptExcerpt`/`.checklist` need a
    /// canvas, attachments, or a transcript this pass doesn't build.
    private static let availableTypes: [NoteBlockType] = [.richText, .decision, .question, .action, .quote]

    init(meeting: Meeting, environment: AppEnvironment, editing: NoteBlock?, onSaved: @escaping (NoteBlock) -> Void) {
        self.meeting = meeting
        self.environment = environment
        self.editing = editing
        self.onSaved = onSaved
        _type = State(initialValue: editing?.type ?? .richText)
        if case .text(let existingText) = editing?.content {
            _text = State(initialValue: existingText)
        } else {
            _text = State(initialValue: "")
        }
        _isPrivate = State(initialValue: (editing?.privacy ?? .privateToAuthor) == .privateToAuthor)
    }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil {
                    Picker("Type", selection: $type) {
                        ForEach(Self.availableTypes, id: \.self) { candidate in
                            Text(candidate.displayName).tag(candidate)
                        }
                    }
                } else {
                    LabeledContent("Type", value: type.displayName)
                }
                TextEditor(text: $text).frame(minHeight: 120)
                Toggle("Private to me", isOn: $isPrivate)
                if let saveError {
                    Text(saveError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
            }
            .navigationTitle(editing == nil ? "New note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let selfPersonID = environment.selfPersonID else {
            saveError = "Setup isn't finished yet — try again in a moment."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let now = environment.clock.now()
        let timestamp = Int64(now.timeIntervalSince1970 * 1000)
        let content = BlockContent.text(text)
        let privacy: BlockPrivacy = isPrivate ? .privateToAuthor : .shared
        let operation = NSPCore.Operation(authorID: selfPersonID, timestamp: timestamp, content: content)

        do {
            if var block = editing {
                block.content = content
                block.privacy = privacy
                block.opLog.append(operation)
                try await environment.noteBlockRepository.update(block, at: now)
                onSaved(block)
            } else {
                // Notes added after the fact have no live recording position
                // to anchor to — anchoring at the meeting's full duration
                // (rather than inventing a specific moment) keeps
                // `creationRange` honest until note-taking during an active
                // recording is wired to `RecordingSession`'s live position.
                let anchorSample = meeting.canonicalDuration.sampleCount
                let block = NoteBlock(
                    blockID: NoteBlockID(rawValue: UUID()), owner: .meeting(meeting.meetingID), authorID: selfPersonID,
                    type: type, content: content,
                    creationRange: SampleRange(startSample: anchorSample, endSample: anchorSample), privacy: privacy,
                    opLog: [operation])
                try await environment.noteBlockRepository.insert(block, at: now)
                onSaved(block)
            }
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}

extension NoteBlockType {
    fileprivate var displayName: String {
        switch self {
        case .richText: return "Note"
        case .checklist: return "Checklist"
        case .decision: return "Decision"
        case .action: return "Action"
        case .quote: return "Quote"
        case .question: return "Question"
        case .code: return "Code"
        case .table: return "Table"
        case .sketch: return "Sketch"
        case .photo: return "Photo"
        case .linkPreview: return "Link"
        case .file: return "File"
        case .transcriptExcerpt: return "Transcript excerpt"
        }
    }

    fileprivate var symbolName: String {
        switch self {
        case .richText: return "note.text"
        case .checklist: return "checklist"
        case .decision: return "checkmark.seal"
        case .action: return "checkmark.circle"
        case .quote: return "quote.opening"
        case .question: return "questionmark.circle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .table: return "tablecells"
        case .sketch: return "scribble"
        case .photo: return "photo"
        case .linkPreview: return "link"
        case .file: return "doc"
        case .transcriptExcerpt: return "text.bubble"
        }
    }
}
