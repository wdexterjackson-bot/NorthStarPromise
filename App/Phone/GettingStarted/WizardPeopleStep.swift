import NSPCore
import NSPDesignSystem
import SwiftUI

/// Step 3 — "who's important." Mirrors `WizardThreadsStep`'s shape:
/// commits a real `Person` the instant it's added, with an optional
/// multi-select of Threads created in the previous step so
/// `thread_participant` is set in the same motion, not a second edit
/// later.
struct WizardPeopleStep: View {
    let coordinator: GettingStartedCoordinator

    @State private var name = ""
    @State private var tag = ""
    @State private var selectedThreadIDs: Set<NSPThreadID> = []

    private static let commonTags = ["Direct report", "Manager", "Board", "Vendor", "Client"]

    var body: some View {
        VStack(alignment: .leading, spacing: NSPSpacing.large) {
            WizardPromptBubble(
                text: "Who do you need me to keep track of? Direct reports, your manager, key partners, vendors, "
                    + "board members — anyone whose meetings and commitments matter to you. I'll track what you "
                    + "owe them and what they owe you, automatically, once it comes up.")

            VStack(spacing: NSPSpacing.small) {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Relationship — e.g. Direct report (optional)", text: $tag).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                HStack(spacing: 6) {
                    ForEach(Self.commonTags, id: \.self) { suggestion in
                        Button(suggestion) { tag = suggestion }
                            .font(Typo.ui(11, .medium))
                            .buttonStyle(.bordered)
                    }
                }
            }

            if !coordinator.createdThreads.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Part of anything above?").font(Typo.ui(12, .semibold)).foregroundStyle(Palette.textSecondary)
                    FlowLayoutWrap {
                        ForEach(coordinator.createdThreads, id: \.threadID) { thread in
                            Button(thread.title) {
                                if selectedThreadIDs.contains(thread.threadID) {
                                    selectedThreadIDs.remove(thread.threadID)
                                } else {
                                    selectedThreadIDs.insert(thread.threadID)
                                }
                            }
                            .font(Typo.ui(11.5, .semibold))
                            .buttonStyle(.bordered)
                            .tint(selectedThreadIDs.contains(thread.threadID) ? Palette.accent.foreground : Palette.textTertiary)
                        }
                    }
                }
            }

            Button("Add") { Task { await add() } }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            if !coordinator.createdPeople.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(coordinator.createdPeople, id: \.personID) { person in
                        HStack {
                            Text(person.name).font(Typo.ui(14, .semibold))
                            if let firstTag = person.tags.first {
                                Text(firstTag).font(Typo.ui(11, .medium)).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func add() async {
        await coordinator.addPerson(name: name, tag: tag, threadIDs: selectedThreadIDs)
        name = ""
        tag = ""
        selectedThreadIDs = []
    }
}

/// A minimal wrapping chip row — `HStack` alone clips instead of wrapping,
/// and this wizard doesn't need a general-purpose flow layout elsewhere in
/// the app, so this stays local rather than joining `NSPDesignSystem`.
struct FlowLayoutWrap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > width, currentRowWidth > 0 {
                totalHeight += rowHeight + 6
                currentRowWidth = 0
                rowHeight = 0
            }
            currentRowWidth += size.width + 6
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + 6
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + 6
            rowHeight = max(rowHeight, size.height)
        }
    }
}
