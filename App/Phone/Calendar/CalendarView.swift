import NSPCore
import NSPDesignSystem
import SwiftUI

/// A month-grid view of this workspace's meetings — genuinely new (iPad's
/// left-panel restructuring introduced this as its own top-header area,
/// not a rename of `ProjectsListView`), built over data this app already
/// has (`Meeting.startedAt`) rather than a new EventKit integration; the
/// device's own calendar events are a separate, larger, deferred feature
/// (`docs/09-BACKLOG.md`'s "Calendar-driven agenda" — reading *external*
/// events, not showing this app's own recordings). Tapping a day shows
/// that day's meetings below the grid; tapping a meeting opens it, same
/// `onSelectMeeting`/`NavigationLink` dual pattern every other list screen
/// in this app uses.
@MainActor
struct CalendarView: View {
    let environment: AppEnvironment
    var onSelectMeeting: ((MeetingID) -> Void)?

    @State private var displayedMonth = Date()
    @State private var selectedDay: Date?
    @State private var meetings: [Meeting] = []
    @State private var loadError: String?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NSPSpacing.large) {
                if let loadError {
                    Text(loadError).font(Typo.ui(11.5, .medium)).foregroundStyle(Palette.danger.foreground)
                }
                monthNavigator
                weekdayHeader
                dayGrid
                Divider().overlay(Palette.divider)
                selectedDaySection
            }
            .padding(NSPSpacing.large)
        }
        .background(Palette.canvas)
        .navigationTitle("Calendar")
        .task { await load() }
        .onChange(of: environment.contentRevision) { _, _ in Task { await load() } }
    }

    // MARK: - Header

    private var monthNavigator: some View {
        HStack {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(Typo.display(28))
            Spacer()
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain).accessibilityLabel("Previous month")
            Button("Today") {
                displayedMonth = Date()
                selectedDay = calendar.startOfDay(for: Date())
            }
            .font(Typo.ui(12, .semibold))
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain).accessibilityLabel("Next month")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                Text(symbol)
                    .font(Typo.ui(10.5, .bold))
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let count = meetingsByDay[calendar.startOfDay(for: day)]?.count ?? 0

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(Typo.ui(13, isToday ? .extrabold : .semibold))
                    .foregroundStyle(isSelected ? .white : (isToday ? Palette.accent.foreground : Palette.textPrimary))
                Circle()
                    .fill(count > 0 ? (isSelected ? .white : Palette.accent.foreground) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                isSelected ? Palette.accent.foreground : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.month(.wide).day().year()))
        .accessibilityValue(count > 0 ? "\(count) meeting\(count == 1 ? "" : "s")" : "No meetings")
    }

    // MARK: - Selected day

    @ViewBuilder
    private var selectedDaySection: some View {
        let day = selectedDay ?? calendar.startOfDay(for: Date())
        let dayMeetings = meetingsByDay[calendar.startOfDay(for: day)] ?? []
        Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(Typo.ui(15, .bold))
        if dayMeetings.isEmpty {
            Text("No meetings this day.").font(Typo.ui(12.5, .medium)).foregroundStyle(Palette.textQuaternary)
        } else {
            ForEach(dayMeetings.sorted { $0.startedAt < $1.startedAt }) { meeting in
                meetingLink(meeting.meetingID) {
                    MeetingRow(meeting: meeting).nspCard()
                }
            }
        }
    }

    @ViewBuilder
    private func meetingLink<Label: View>(_ meetingID: MeetingID, @ViewBuilder label: () -> Label) -> some View {
        if let onSelectMeeting {
            Button {
                onSelectMeeting(meetingID)
            } label: {
                label()
            }.buttonStyle(.plain)
        } else {
            NavigationLink(value: meetingID) { label() }.buttonStyle(.plain)
        }
    }

    // MARK: - Data

    private var meetingsByDay: [Date: [Meeting]] {
        Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.startedAt) }
    }

    /// `nil` entries are the leading blanks before the 1st falls on the
    /// grid's first column — `LazyVGrid` just renders them as empty cells.
    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: monthInterval.start) }
        return Array(repeating: nil, count: leadingBlanks) + days
    }

    private func shiftMonth(by delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = newMonth
    }

    private static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func load() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            meetings = try await environment.meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)
            if selectedDay == nil { selectedDay = calendar.startOfDay(for: Date()) }
        } catch {
            loadError = "\(error)"
        }
    }
}
