import NSPCore
import NSPDesignSystem
import SwiftUI

/// Step 2 — "what's on your plate." Each row commits as a real `NSPThread`
/// the moment it's added (`GettingStartedCoordinator.addThread`), not on
/// "Continue" — so a Thread mentioned here already exists, and already
/// shows up on My Work, before the wizard even finishes.
struct WizardThreadsStep: View {
    let coordinator: GettingStartedCoordinator

    @State private var title = ""
    @State private var kind: ThreadKind = .initiative

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "Tell me what you're actively juggling right now — the big things, not every task. I'll "
                    + "call each one a Thread: a storyline that runs through several meetings, notes, and people "
                    + "over time.")

            HStack(spacing: NSPSpacing.small) {
                TextField("e.g. Q3 board renewal", text: $title).textFieldStyle(.roundedBorder)
                Button("Add") { Task { await add() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Picker("Kind", selection: $kind) {
                ForEach(ThreadKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            if !coordinator.createdThreads.isEmpty {
                VStack(alignment: .leading, spacing: NSPSpacing.small) {
                    ForEach(coordinator.createdThreads, id: \.threadID) { thread in
                        HStack {
                            Circle().fill(Palette.threadSlots[thread.colorSlot]).frame(width: 8, height: 8)
                            Text(thread.title).font(Typo.ui(14, .semibold))
                            Text(thread.kind.displayName).font(Typo.ui(11, .medium)).foregroundStyle(Palette.textTertiary)
                            Spacer()
                            Button {
                                Task { await coordinator.removeThread(thread.threadID) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textQuaternary)
                            }
                        }
                    }
                }
                Text("These show up on My Work with their next meeting and open actions the moment you save this.")
                    .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            } else {
                Text("Most execs start with 3–5. Zero is fine too — you can add these anytime from Threads.")
                    .font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func add() async {
        await coordinator.addThread(title: title, kind: kind)
        title = ""
    }
}
