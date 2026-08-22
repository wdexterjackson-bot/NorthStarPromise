import NSPCore
import NSPDesignSystem
import SwiftUI

/// Every extracted item lands here first — never auto-added anywhere.
/// Accept promotes it to a real `Action`/`Decision`; reject discards it
/// with nothing left behind ("Overheard" recommendation, 2026-08-22).
struct AmbientSuggestionsInboxView: View {
    let environment: AppEnvironment

    @State private var suggestions: [AmbientSuggestion] = []
    @State private var threadTitles: [NSPThreadID: String] = [:]
    @State private var personNames: [PersonID: String] = [:]
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load suggestions", systemImage: "exclamationmark.triangle",
                    description: Text(loadError))
            } else if suggestions.isEmpty {
                ContentUnavailableView(
                    "Nothing waiting", systemImage: "sparkles",
                    description: Text("Exercise Mode's catches show up here for you to review."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                        ForEach(suggestions) { suggestion in
                            AmbientSuggestionRowView(
                                suggestion: suggestion, threadTitle: suggestion.threadID.flatMap { threadTitles[$0] },
                                personName: suggestion.counterpartyID.flatMap { personNames[$0] },
                                onAccept: { Task { await accept(suggestion) } },
                                onReject: { Task { await reject(suggestion) } })
                        }
                    }
                    .padding(NSPSpacing.large)
                }
                .background(Palette.canvas)
            }
        }
        .navigationTitle("Ambient Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            suggestions = try await environment.ambientSuggestionRepository.fetchPending(workspaceID: workspaceID)
            let threads = try await environment.threadRepository.fetchAll(workspaceID: workspaceID)
            threadTitles = Dictionary(uniqueKeysWithValues: threads.map { ($0.threadID, $0.title) })
            let people = try await environment.personRepository.fetchAll(workspaceID: workspaceID)
            personNames = Dictionary(uniqueKeysWithValues: people.map { ($0.personID, $0.name) })
        } catch {
            loadError = "\(error)"
        }
    }

    /// Accepting a suggestion creates a real, freestanding `Action` with
    /// `evidence: []` — a human directly confirmed this, not an AI
    /// extraction from a transcript (same reasoning `ActionComposerView`
    /// already uses for manually-created actions; Invariant I4 doesn't
    /// apply). `AmbientEvidence` stays on the suggestion row itself as the
    /// record of where this came from, never copied into the real
    /// `Action`'s own evidence field.
    ///
    /// Always an `Action`, even for `.decision`-kind suggestions —
    /// `Decision.meetingID` is non-optional by design (`docs/02`: "a
    /// decision is always made *in* a specific meeting, never
    /// freestanding"), and Ambient Mode never has one. `.decision` still
    /// earns its keep as an extraction/labeling signal (the inbox shows
    /// "Decision," and the underlying text reads as one), but the ledger
    /// entry it becomes is an `Action` either way.
    private func accept(_ suggestion: AmbientSuggestion) async {
        guard let selfPersonID = environment.selfPersonID else { return }
        let now = environment.clock.now()
        do {
            // The heuristic extractor doesn't detect *who* is committing,
            // only that a commitment was made — `.iOwe` is the same safe
            // default `ActionComposerView` already uses when direction
            // can't be determined; the user can change it after accepting.
            let action = Action(
                actionID: .generate(clock: environment.clock), workspaceID: suggestion.workspaceID,
                threadID: suggestion.threadID, counterpartyID: suggestion.counterpartyID, text: suggestion.text,
                direction: .iOwe, evidence: [], createdBy: selfPersonID,
                auditTrail: [AuditEntry(actorID: selfPersonID, action: "proposed", at: now)])
            try await environment.actionRepository.insert(action, at: now)
            var updated = suggestion
            updated.status = .accepted
            try await environment.ambientSuggestionRepository.update(updated, at: now)
            suggestions.removeAll { $0.ambientSuggestionID == suggestion.ambientSuggestionID }
        } catch {
            loadError = "\(error)"
        }
    }

    private func reject(_ suggestion: AmbientSuggestion) async {
        var updated = suggestion
        updated.status = .rejected
        do {
            try await environment.ambientSuggestionRepository.update(updated, at: environment.clock.now())
            suggestions.removeAll { $0.ambientSuggestionID == suggestion.ambientSuggestionID }
        } catch {
            loadError = "\(error)"
        }
    }
}

private struct AmbientSuggestionRowView: View {
    let suggestion: AmbientSuggestion
    let threadTitle: String?
    let personName: String?
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.small) {
            HStack(spacing: 6) {
                Text(suggestion.kind == .decision ? "Decision" : "Action")
                    .font(Typo.ui(10.5, .bold))
                    .foregroundStyle(Palette.textTertiary)
                if let threadTitle {
                    Text("· \(threadTitle)").font(Typo.ui(10.5, .semibold)).foregroundStyle(Palette.textTertiary)
                }
                if let personName {
                    Text("· \(personName)").font(Typo.ui(10.5, .semibold)).foregroundStyle(Palette.textTertiary)
                }
            }
            Text(suggestion.text).font(Typo.ui(14.5, .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("From Exercise Mode — no recording exists").font(Typo.ui(10.5, .medium))
                    .foregroundStyle(Palette.textQuaternary)
                Text("\"\(suggestion.evidence.excerpt)\"").font(Typo.ui(11.5, .medium)).italic()
                    .foregroundStyle(Palette.textTertiary).lineLimit(3)
            }
            HStack(spacing: NSPSpacing.medium) {
                Button("Accept", action: onAccept).buttonStyle(.borderedProminent)
                Button("Dismiss", role: .destructive, action: onReject).buttonStyle(.bordered)
            }
            .font(Typo.ui(12.5, .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NSPSpacing.medium)
        .nspCard()
    }
}
