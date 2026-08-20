import Foundation
import NSPCore
import NSPMedia
import PencilKit

// Split out of `PadRecordingCanvas.swift` to stay under SwiftLint's
// file-length cap — the `@State` vars and helpers this extension needs
// are declared without `private` in the main file for exactly that reason
// (`private` doesn't cross files, even between extensions of the same type).
extension PadRecordingCanvas {
    /// `PadInkCanvas` reports the whole drawing on every change; strokes
    /// past the count we last saw are the new ones (PencilKit only ever
    /// appends to `PKDrawing.strokes`), computed from the *previous*
    /// `drawing` before it's overwritten.
    func handleDrawingChange(_ newDrawing: PKDrawing) {
        let previousCount = drawing.strokes.count
        drawing = newDrawing
        guard newDrawing.strokes.count > previousCount else { return }
        let newStrokes = Array(newDrawing.strokes[previousCount...])
        Task { await handleStrokesAdded(newStrokes) }
    }

    /// Feeds every newly-drawn stroke into `StrokeGroupTracker`, persisting
    /// whichever group closes as a result, and (re-)arms the idle-close
    /// timer so a group left open with no further strokes still gets
    /// stamped and saved rather than waiting forever for one more stroke.
    func handleStrokesAdded(_ strokes: [PKStroke]) async {
        guard !strokes.isEmpty else { return }
        if strokeTracker == nil {
            let sampleRate = await session.currentSampleRate() ?? 48000
            strokeTracker = StrokeGroupTracker(sampleRate: sampleRate)
        }
        let isPreRecording = session.state == .draft
        let batchSampleOffset = isPreRecording ? nil : (await session.currentSampleOffset() ?? 0)
        for stroke in strokes {
            let strokeID = UUID()
            strokesByID[strokeID] = stroke
            let sampleOffset = batchSampleOffset ?? reservePreRecordingSampleOffset()
            let event = InkStrokeEvent(strokeID: strokeID, boundingBox: stroke.renderBounds, sampleOffset: sampleOffset)
            if let closedGroup = strokeTracker?.handle(event) {
                await persist(group: closedGroup)
            }
        }
        armIdleGroupCloseTimer()
    }

    func armIdleGroupCloseTimer() {
        idleGroupCloseTask?.cancel()
        idleGroupCloseTask = Task {
            try? await Task.sleep(for: Self.idleGroupCloseDelay)
            guard !Task.isCancelled else { return }
            await closeOpenInkGroupIfNeeded()
        }
    }

    /// Force-closes whatever ink group is open — called by the idle timer,
    /// on tool switch away from Pen, on Stop, and when the canvas leaves
    /// the screen, so a group is never left unpersisted indefinitely.
    func closeOpenInkGroupIfNeeded() async {
        idleGroupCloseTask?.cancel()
        idleGroupCloseTask = nil
        if let closedGroup = strokeTracker?.closeOpenGroup() {
            await persist(group: closedGroup)
        }
    }

    func persist(group: InkStrokeGroup) async {
        guard let meetingID = session.meetingID, let selfPersonID = environment.selfPersonID,
            let container = session.meetingContainer
        else { return }
        let groupStrokes = group.strokeIDs.compactMap { strokesByID[$0] }
        for id in group.strokeIDs { strokesByID.removeValue(forKey: id) }
        guard !groupStrokes.isEmpty else { return }

        let filename = "\(UUID().uuidString).drawing"
        let relativePath = "ink/\(filename)"
        let assetURL = container.inkDirectoryURL.appendingPathComponent(filename)
        let now = environment.clock.now()

        do {
            let data = PKDrawing(strokes: groupStrokes).dataRepresentation()
            try environment.inkAssetFileSystem.write(data, to: assetURL)
            let content = BlockContent.assetReference(path: relativePath)
            let block = NoteBlock(
                blockID: NoteBlockID(rawValue: UUID()), meetingID: meetingID, authorID: selfPersonID, type: .sketch,
                content: content, creationRange: group.sampleRange, privacy: .shared,
                opLog: [
                    Operation(authorID: selfPersonID, timestamp: Self.millisecondTimestamp(now), content: content)
                ])
            try await environment.noteBlockRepository.insert(block, at: now)
        } catch {
            loadError = "\(error)"
        }
    }

    /// Restores every already-persisted `.sketch` block's strokes into one
    /// composited `PKDrawing` for display — each block keeps its own
    /// `creationRange` in the database; only strokes drawn *after* this
    /// load feed the tracker (`handleDrawingChange`'s count-diff already
    /// treats everything in the restored `drawing` as a fixed baseline).
    func loadExistingInk() async {
        guard let meetingID = session.meetingID, let container = session.meetingContainer else { return }
        do {
            let blocks = try await environment.noteBlockRepository.fetchAll(meetingID: meetingID)
            let sketchBlocks = blocks.filter { $0.type == .sketch }
            var strokes: [PKStroke] = []
            for block in sketchBlocks {
                guard case .assetReference(let path) = block.content else { continue }
                let url = container.rootURL.appendingPathComponent(path)
                let data = try environment.inkAssetFileSystem.read(from: url)
                strokes.append(contentsOf: try PKDrawing(data: data).strokes)
            }
            drawing = PKDrawing(strokes: strokes)
        } catch {
            loadError = "\(error)"
        }
    }
}
