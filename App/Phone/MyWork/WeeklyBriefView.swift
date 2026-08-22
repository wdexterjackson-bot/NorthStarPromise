import NSPCore
import NSPDesignSystem
import NSPIntelligence
import SwiftUI

/// The Monday-morning brief "The Spine" recommendation calls for
/// (2026-08-22) — reached from `MyWorkView`'s toolbar, and the destination
/// `WeeklyBriefScheduler`'s local notification opens into. Default-on for
/// every workspace: no settings gate, matches the recommendation's chosen
/// call.
struct WeeklyBriefView: View {
    let environment: AppEnvironment
    var onSelectThread: ((NSPThreadID) -> Void)?
    var onSelectPerson: ((PersonID) -> Void)?

    @State private var brief: WeeklyBrief?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load the brief", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let brief {
                ScrollView {
                    VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                        Text("Week of \(brief.weekOf.formatted(.dateTime.month(.wide).day()))")
                            .font(Typo.ui(13, .semibold)).foregroundStyle(Palette.textTertiary)
                        Text(brief.summary).font(Typo.display(22))

                        section(title: "Threads gone quiet") {
                            if brief.quietThreads.isEmpty {
                                emptyLine("Nothing's gone quiet — every open thread has recent activity.")
                            } else {
                                ForEach(brief.quietThreads) { entry in
                                    Button { onSelectThread?(entry.threadID) } label: {
                                        rowLine(entry.title, "Quiet \(entry.quietDays)d")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        section(title: "People waiting on you") {
                            if brief.overdueFollowUps.isEmpty {
                                emptyLine("Nobody's waiting on an overdue follow-up.")
                            } else {
                                ForEach(brief.overdueFollowUps) { entry in
                                    Button { onSelectPerson?(entry.personID) } label: {
                                        rowLine(entry.personName, "\(entry.openCount) open")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        section(title: "Last week's decisions") {
                            if brief.decisionsLastWeek.isEmpty {
                                emptyLine("No decisions logged last week.")
                            } else {
                                ForEach(brief.decisionsLastWeek) { decision in
                                    Text(decision.text).font(Typo.ui(14, .semibold)).nspCard()
                                }
                            }
                        }
                    }
                    .padding(NSPSpacing.large)
                }
                .background(Palette.canvas)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Weekly Brief")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: NSPSpacing.medium) {
            Text(title).font(Typo.ui(17, .extrabold))
            content()
        }
    }

    private func rowLine(_ leading: String, _ trailing: String) -> some View {
        HStack {
            Text(leading).font(Typo.ui(14, .semibold)).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(trailing).font(Typo.ui(12, .semibold)).foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textQuaternary)
    }

    private func load() async {
        do {
            brief = try await environment.composeWeeklyBrief()
        } catch {
            loadError = "\(error)"
        }
    }
}
