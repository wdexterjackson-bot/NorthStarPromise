import Foundation

/// Pure, `Date`-parameterized expansion of a `RecurrenceRule` into concrete
/// occurrence dates within a bounded window — display only (NSP-157).
/// Nothing here writes to a repository or materializes a row; a `Meeting`/
/// `ScheduledRecording` only becomes real the moment an occurrence is
/// actually started, exactly like a non-recurring item today. Same "pure
/// function over an injected `Calendar`, no ambient `Date()`" shape as
/// `ScheduledRecordingScheduling` (`docs/11` §4).
public enum RecurrenceExpander {
    /// Occurrence dates for `rule`, starting from `seriesStart`, that fall
    /// within `window` (inclusive both ends) — `RecurrenceEnd` and the
    /// window each independently bound the expansion; whichever is
    /// reached first stops it. `seriesStart` is trusted to already sit on
    /// a date the rule's pattern would itself produce (e.g. a `.weekly`
    /// rule's start falls on one of its own `days`) — this function only
    /// projects forward from it, it never validates or corrects it.
    public static func occurrences(
        of rule: RecurrenceRule,
        seriesStart: Date,
        in window: ClosedRange<Date>,
        calendar: Calendar
    ) -> [Date] {
        var results: [Date] = []
        var current = seriesStart
        var emitted = 0
        var iterations = 0
        let hardCap = 10_000

        while iterations < hardCap {
            iterations += 1
            if case .onDate(let endDate) = rule.end, current > endDate { break }
            if case .afterOccurrences(let limit) = rule.end, emitted >= limit { break }
            if current > window.upperBound { break }

            emitted += 1
            if current >= window.lowerBound {
                results.append(current)
            }

            guard let next = nextDate(after: current, seriesStart: seriesStart, rule: rule, calendar: calendar)
            else { break }
            current = next
        }

        return results
    }

    private static func nextDate(
        after date: Date, seriesStart: Date, rule: RecurrenceRule, calendar: Calendar
    ) -> Date? {
        switch rule.frequency {
        case .daily(let interval, let everyWeekday):
            if everyWeekday {
                var next = calendar.date(byAdding: .day, value: 1, to: date)
                while let candidate = next, calendar.isDateInWeekend(candidate) {
                    next = calendar.date(byAdding: .day, value: 1, to: candidate)
                }
                return next
            }
            return calendar.date(byAdding: .day, value: max(interval, 1), to: date)

        case .weekly(let interval, let days):
            return nextWeeklyDate(after: date, seriesStart: seriesStart, interval: interval, days: days, calendar: calendar)

        case .monthly(let interval, let pattern):
            guard
                let anchor = calendar.date(
                    byAdding: .month, value: max(interval, 1), to: startOfMonth(date, calendar: calendar)),
                let day = dateFor(pattern: pattern, monthAnchor: anchor, calendar: calendar)
            else { return nil }
            return applyTimeOfDay(from: seriesStart, onto: day, calendar: calendar)

        case .yearly(let month, let pattern):
            var comps = calendar.dateComponents([.year], from: date)
            comps.year = (comps.year ?? 0) + 1
            comps.month = month
            comps.day = 1
            guard let anchor = calendar.date(from: comps),
                let day = dateFor(pattern: pattern, monthAnchor: anchor, calendar: calendar)
            else { return nil }
            return applyTimeOfDay(from: seriesStart, onto: day, calendar: calendar)
        }
    }

    private static func nextWeeklyDate(
        after date: Date, seriesStart: Date, interval: Int, days: Set<Weekday>, calendar: Calendar
    ) -> Date? {
        guard !days.isEmpty else { return nil }
        let normalizedInterval = max(interval, 1)
        let seriesWeekStart = startOfWeek(containing: seriesStart, calendar: calendar)
        guard var candidate = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }

        var steps = 0
        while steps < 400 {
            steps += 1
            if let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)), days.contains(weekday) {
                let candidateWeekStart = startOfWeek(containing: candidate, calendar: calendar)
                let weeksBetween =
                    calendar.dateComponents([.weekOfYear], from: seriesWeekStart, to: candidateWeekStart).weekOfYear
                    ?? 0
                if weeksBetween % normalizedInterval == 0 {
                    return candidate
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return nil
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private static func dateFor(pattern: MonthlyPattern, monthAnchor: Date, calendar: Calendar) -> Date? {
        switch pattern {
        case .dayOfMonth(let day):
            var comps = calendar.dateComponents([.year, .month], from: monthAnchor)
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 28
            comps.day = min(max(day, 1), daysInMonth)
            return calendar.date(from: comps)

        case .relativeWeekday(let ordinal, let weekday):
            return nthWeekday(ordinal, weekday, in: monthAnchor, calendar: calendar)
        }
    }

    private static func nthWeekday(
        _ ordinal: WeekdayOrdinal, _ weekday: Weekday, in monthAnchor: Date, calendar: Calendar
    ) -> Date? {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else { return nil }
        var matches: [Date] = []
        var cursor = monthInterval.start
        while cursor < monthInterval.end {
            if calendar.component(.weekday, from: cursor) == weekday.calendarComponentValue {
                matches.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        switch ordinal {
        case .first: return matches.first
        case .second: return matches.count > 1 ? matches[1] : nil
        case .third: return matches.count > 2 ? matches[2] : nil
        case .fourth: return matches.count > 3 ? matches[3] : nil
        case .last: return matches.last
        }
    }

    private static func applyTimeOfDay(from seriesStart: Date, onto day: Date, calendar: Calendar) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: seriesStart)
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = time.second
        return calendar.date(from: comps)
    }
}
