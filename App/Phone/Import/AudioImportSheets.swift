import NSPCore
import NSPDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The whole "Import Recording" flow, attached once at the same level a
/// screen's capture button lives (mirrors `TodayPromptSheets`'s own
/// root-adjacent placement): file picker → durable import
/// (`AudioImportCoordinator`) → the same `MeetingTitlePromptView` a live
/// recording shows, so an imported meeting picks up a title, project
/// links, and AI-processing choices through the identical, already-trusted
/// path rather than a parallel shortcut.
@MainActor
struct AudioImportSheets: ViewModifier {
    @Binding var isShowingPicker: Bool
    let environment: AppEnvironment
    /// Called once the title prompt is dismissed (saved or deleted) — the
    /// caller's cue to refresh whatever list is showing meetings.
    let onDone: () -> Void

    @State private var isImporting = false
    @State private var importError: String?
    @State private var pendingTitleMeeting: Meeting?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isShowingPicker, allowedContentTypes: [.mp3, .wav, .mpeg4Audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await performImport(from: url) }
                case .failure(let error):
                    importError = "\(error)"
                }
            }
            .overlay { if isImporting { ImportProgressOverlay() } }
            .alert(
                "Couldn't import audio",
                isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(item: $pendingTitleMeeting) { meeting in
                MeetingTitlePromptView(
                    meeting: meeting, environment: environment,
                    onSave: { updated, options in
                        pendingTitleMeeting = nil
                        if let selfPersonID = environment.selfPersonID {
                            let intelligence = environment.intelligenceCoordinator
                            Task {
                                await intelligence.processMeeting(
                                    updated.meetingID, selfPersonID: selfPersonID, options: options)
                            }
                        }
                        onDone()
                    },
                    onDelete: {
                        let meetingID = pendingTitleMeeting?.meetingID
                        pendingTitleMeeting = nil
                        if let meetingID {
                            Task { try? await environment.deleteMeeting(meetingID) }
                        }
                        onDone()
                    })
            }
    }

    private func performImport(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let coordinator = AudioImportCoordinator(environment: environment)
            pendingTitleMeeting = try await coordinator.importAudio(from: url)
        } catch {
            importError = "\(error)"
        }
    }
}

private struct ImportProgressOverlay: View {
    var body: some View {
        ZStack {
            Palette.canvas.opacity(0.6).ignoresSafeArea()
            VStack(spacing: NSPSpacing.medium) {
                ProgressView()
                Text("Importing audio…").font(Typo.ui(13, .semibold)).foregroundStyle(Palette.textSecondary)
            }
            .padding(NSPSpacing.extraLarge)
            .background(Palette.surface, in: .rect(cornerRadius: 16, style: .continuous))
        }
    }
}

extension View {
    /// Attaches the import-audio picker + progress + title-prompt flow.
    /// `isShowingPicker` is owned by the caller (typically a `@State` the
    /// capture button's "Import Recording" menu item flips to `true`).
    func audioImportSheets(
        isShowingPicker: Binding<Bool>, environment: AppEnvironment, onDone: @escaping () -> Void
    ) -> some View {
        modifier(AudioImportSheets(isShowingPicker: isShowingPicker, environment: environment, onDone: onDone))
    }
}
