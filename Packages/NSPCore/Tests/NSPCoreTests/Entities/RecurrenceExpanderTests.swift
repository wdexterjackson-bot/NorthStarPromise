import Foundation
import Testing

@testable import NSPCore

@Suite("RecurrenceExpander")
struct RecurrenceExpanderTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return utcCalendar.date(from: comps)!
    }

    private static func rule(
        frequency: RecurrenceFrequency, end: RecurrenceEnd = .never
    ) -> RecurrenceRule {
        RecurrenceRule(
            recurrenceRuleID: .generate(clock: SystemClock()), workspaceID: .generate(clock: SystemClock()),
            frequency: frequency, end: end, createdAt: Date(), updatedAt: Date())
    }

    @Test func test_daily_everyInterval() {
        let seriesStart = Self.date(2026, 1, 1)
        let rule = Self.rule(frequency: .daily(interval: 2))
        let window = seriesStart...Self.date(2026, 1, 10)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        #expect(occurrences == [1, 3, 5, 7, 9].map { Self.date(2026, 1, $0) })
    }

    @Test func test_daily_everyWeekday_skipsWeekends() {
        // 2026-01-01 is a Thursday.
        let seriesStart = Self.date(2026, 1, 1)
        let rule = Self.rule(frequency: .daily(interval: 1, everyWeekday: true))
        let window = seriesStart...Self.date(2026, 1, 9)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        // Thu 1, Fri 2, (skip Sat 3/Sun 4), Mon 5, Tue 6, Wed 7, Thu 8, Fri 9.
        #expect(occurrences == [1, 2, 5, 6, 7, 8, 9].map { Self.date(2026, 1, $0) })
    }

    @Test func test_weekly_multipleDays_respectsInterval() {
        // 2026-01-05 is a Monday.
        let seriesStart = Self.date(2026, 1, 5)
        let rule = Self.rule(frequency: .weekly(interval: 2, days: [.monday, .wednesday]))
        let window = seriesStart...Self.date(2026, 2, 1)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        // Week 1 (Jan 5-11): Mon 5, Wed 7. Week 2 skipped (interval 2). Week 3 (Jan 19-25): Mon 19, Wed 21.
        #expect(occurrences == [5, 7, 19, 21].map { Self.date(2026, 1, $0) })
    }

    @Test func test_monthly_dayOfMonth_clampsToShorterMonths() {
        let seriesStart = Self.date(2026, 1, 31)
        let rule = Self.rule(frequency: .monthly(interval: 1, pattern: .dayOfMonth(31)))
        let window = seriesStart...Self.date(2026, 4, 30)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        // Feb has 28 days in 2026, March has 31, April has 30.
        #expect(occurrences == [Self.date(2026, 1, 31), Self.date(2026, 2, 28), Self.date(2026, 3, 31), Self.date(2026, 4, 30)])
    }

    @Test func test_monthly_relativeWeekday() {
        // Second Tuesday of January 2026 is Jan 13.
        let seriesStart = Self.date(2026, 1, 13)
        let rule = Self.rule(frequency: .monthly(interval: 1, pattern: .relativeWeekday(.second, .tuesday)))
        let window = seriesStart...Self.date(2026, 3, 31)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        #expect(occurrences == [Self.date(2026, 1, 13), Self.date(2026, 2, 10), Self.date(2026, 3, 10)])
    }

    @Test func test_yearly_advancesOneYearAtATime() {
        let seriesStart = Self.date(2026, 3, 15)
        let rule = Self.rule(frequency: .yearly(month: 3, pattern: .dayOfMonth(15)))
        let window = seriesStart...Self.date(2029, 12, 31)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        #expect(occurrences == [2026, 2027, 2028, 2029].map { Self.date($0, 3, 15) })
    }

    @Test func test_end_afterOccurrences_stopsExactlyAtLimit() {
        let seriesStart = Self.date(2026, 1, 1)
        let rule = Self.rule(frequency: .daily(interval: 1), end: .afterOccurrences(3))
        let window = seriesStart...Self.date(2026, 1, 31)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        #expect(occurrences == [1, 2, 3].map { Self.date(2026, 1, $0) })
    }

    @Test func test_end_onDate_excludesOccurrencesAfterTheEndDate() {
        let seriesStart = Self.date(2026, 1, 1)
        let rule = Self.rule(frequency: .daily(interval: 1), end: .onDate(Self.date(2026, 1, 3, 23)))
        let window = seriesStart...Self.date(2026, 1, 31)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        #expect(occurrences == [1, 2, 3].map { Self.date(2026, 1, $0) })
    }

    @Test func test_window_excludesOccurrencesBeforeItsLowerBound() {
        let seriesStart = Self.date(2026, 1, 1)
        let rule = Self.rule(frequency: .daily(interval: 1))
        let window = Self.date(2026, 1, 5)...Self.date(2026, 1, 7)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        #expect(occurrences == [5, 6, 7].map { Self.date(2026, 1, $0) })
    }

    @Test func test_preservesTimeOfDayForMonthlyOccurrences() {
        let seriesStart = Self.date(2026, 1, 15, 14)
        let rule = Self.rule(frequency: .monthly(interval: 1, pattern: .dayOfMonth(15)))
        let window = seriesStart...Self.date(2026, 3, 31)
        let occurrences = RecurrenceExpander.occurrences(
            of: rule, seriesStart: seriesStart, in: window, calendar: Self.utcCalendar)
        for occurrence in occurrences {
            #expect(Self.utcCalendar.component(.hour, from: occurrence) == 14)
        }
    }
}
