import NSPCore
import NSPDesignSystem
import SwiftUI

/// "Make Event Recurring"'s secondary sheet (NSP-158) — mirrors Outlook's
/// own recurrence dialog: a Daily/Weekly/Monthly/Yearly segmented control,
/// the pattern-specific controls, and a "Range of recurrence" section.
/// Hands an in-memory `RecurrenceFrequency`/`RecurrenceEnd` back to the
/// parent form via `onDone` — nothing is persisted here; `AddAgendaItemFormView`
/// only writes a `RecurrenceRule` row once the whole event itself is saved,
/// same pattern the color and Meeting Type pickers already use in that form.
struct RecurrenceConfigurationView: View {
    let seriesStart: Date
    var initialFrequency: RecurrenceFrequency?
    var initialEnd: RecurrenceEnd
    let onDone: (RecurrenceFrequency, RecurrenceEnd) -> Void
    var onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    private enum FrequencyKind: String, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
    }

    private enum PatternKind: String, CaseIterable, Identifiable {
        case dayOfMonth, relativeWeekday
        var id: String { rawValue }
    }

    private enum EndKind: String, CaseIterable, Identifiable {
        case never, afterOccurrences, onDate
        var id: String { rawValue }
    }

    @State private var frequencyKind: FrequencyKind
    @State private var interval: Int
    @State private var everyWeekdayOnly: Bool
    @State private var selectedDays: Set<Weekday>
    @State private var yearlyMonth: Int
    @State private var patternKind: PatternKind
    @State private var patternDay: Int
    @State private var patternOrdinal: WeekdayOrdinal
    @State private var patternWeekday: Weekday
    @State private var endKind: EndKind
    @State private var endOccurrences: Int
    @State private var endDate: Date

    init(
        seriesStart: Date, initialFrequency: RecurrenceFrequency?, initialEnd: RecurrenceEnd,
        onDone: @escaping (RecurrenceFrequency, RecurrenceEnd) -> Void, onRemove: (() -> Void)? = nil
    ) {
        self.seriesStart = seriesStart
        self.initialFrequency = initialFrequency
        self.initialEnd = initialEnd
        self.onDone = onDone
        self.onRemove = onRemove

        let calendar = Calendar.current
        let seededWeekday = Weekday(rawValue: calendar.component(.weekday, from: seriesStart)) ?? .monday
        let seededDay = calendar.component(.day, from: seriesStart)
        let seededMonth = calendar.component(.month, from: seriesStart)
        let seededOrdinal = Self.ordinal(ofWeekday: seriesStart, calendar: calendar)

        switch initialFrequency {
        case .daily(let interval, let everyWeekday):
            _frequencyKind = State(initialValue: .daily)
            _interval = State(initialValue: interval)
            _everyWeekdayOnly = State(initialValue: everyWeekday)
            _selectedDays = State(initialValue: [seededWeekday])
            _patternKind = State(initialValue: .dayOfMonth)
            _patternDay = State(initialValue: seededDay)
            _patternOrdinal = State(initialValue: seededOrdinal)
            _patternWeekday = State(initialValue: seededWeekday)
            _yearlyMonth = State(initialValue: seededMonth)
        case .weekly(let interval, let days):
            _frequencyKind = State(initialValue: .weekly)
            _interval = State(initialValue: interval)
            _everyWeekdayOnly = State(initialValue: false)
            _selectedDays = State(initialValue: days.isEmpty ? [seededWeekday] : days)
            _patternKind = State(initialValue: .dayOfMonth)
            _patternDay = State(initialValue: seededDay)
            _patternOrdinal = State(initialValue: seededOrdinal)
            _patternWeekday = State(initialValue: seededWeekday)
            _yearlyMonth = State(initialValue: seededMonth)
        case .monthly(let interval, let pattern):
            _frequencyKind = State(initialValue: .monthly)
            _interval = State(initialValue: interval)
            _everyWeekdayOnly = State(initialValue: false)
            _selectedDays = State(initialValue: [seededWeekday])
            _yearlyMonth = State(initialValue: seededMonth)
            switch pattern {
            case .dayOfMonth(let day):
                _patternKind = State(initialValue: .dayOfMonth)
                _patternDay = State(initialValue: day)
                _patternOrdinal = State(initialValue: seededOrdinal)
                _patternWeekday = State(initialValue: seededWeekday)
            case .relativeWeekday(let ordinal, let weekday):
                _patternKind = State(initialValue: .relativeWeekday)
                _patternDay = State(initialValue: seededDay)
                _patternOrdinal = State(initialValue: ordinal)
                _patternWeekday = State(initialValue: weekday)
            }
        case .yearly(let month, let pattern):
            _frequencyKind = State(initialValue: .yearly)
            _interval = State(initialValue: 1)
            _everyWeekdayOnly = State(initialValue: false)
            _selectedDays = State(initialValue: [seededWeekday])
            _yearlyMonth = State(initialValue: month)
            switch pattern {
            case .dayOfMonth(let day):
                _patternKind = State(initialValue: .dayOfMonth)
                _patternDay = State(initialValue: day)
                _patternOrdinal = State(initialValue: seededOrdinal)
                _patternWeekday = State(initialValue: seededWeekday)
            case .relativeWeekday(let ordinal, let weekday):
                _patternKind = State(initialValue: .relativeWeekday)
                _patternDay = State(initialValue: seededDay)
                _patternOrdinal = State(initialValue: ordinal)
                _patternWeekday = State(initialValue: weekday)
            }
        case nil:
            _frequencyKind = State(initialValue: .weekly)
            _interval = State(initialValue: 1)
            _everyWeekdayOnly = State(initialValue: false)
            _selectedDays = State(initialValue: [seededWeekday])
            _patternKind = State(initialValue: .dayOfMonth)
            _patternDay = State(initialValue: seededDay)
            _patternOrdinal = State(initialValue: seededOrdinal)
            _patternWeekday = State(initialValue: seededWeekday)
            _yearlyMonth = State(initialValue: seededMonth)
        }

        switch initialEnd {
        case .never:
            _endKind = State(initialValue: .never)
            _endOccurrences = State(initialValue: 10)
            _endDate = State(initialValue: seriesStart.addingTimeInterval(86400 * 30))
        case .afterOccurrences(let count):
            _endKind = State(initialValue: .afterOccurrences)
            _endOccurrences = State(initialValue: count)
            _endDate = State(initialValue: seriesStart.addingTimeInterval(86400 * 30))
        case .onDate(let date):
            _endKind = State(initialValue: .onDate)
            _endOccurrences = State(initialValue: 10)
            _endDate = State(initialValue: date)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern") {
                    Picker("Repeats", selection: $frequencyKind) {
                        ForEach(FrequencyKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                patternSection
                Section("Range of recurrence") {
                    LabeledContent("Start") { Text(seriesStart, style: .date) }
                    Picker("Ends", selection: $endKind) {
                        Text("Never").tag(EndKind.never)
                        Text("After").tag(EndKind.afterOccurrences)
                        Text("On date").tag(EndKind.onDate)
                    }
                    if endKind == .afterOccurrences {
                        Stepper("\(endOccurrences) occurrences", value: $endOccurrences, in: 1...999)
                    }
                    if endKind == .onDate {
                        DatePicker("End date", selection: $endDate, in: seriesStart..., displayedComponents: .date)
                    }
                }
                if onRemove != nil {
                    Section {
                        Button("Remove Recurrence", role: .destructive) {
                            onRemove?()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Make Event Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(builtFrequency, builtEnd)
                        dismiss()
                    }
                    .disabled(frequencyKind == .weekly && selectedDays.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var patternSection: some View {
        switch frequencyKind {
        case .daily:
            Section("Daily") {
                Toggle("Every weekday", isOn: $everyWeekdayOnly)
                if !everyWeekdayOnly {
                    Stepper("Every \(interval) day\(interval == 1 ? "" : "s")", value: $interval, in: 1...365)
                }
            }
        case .weekly:
            Section("Weekly") {
                Stepper("Every \(interval) week\(interval == 1 ? "" : "s")", value: $interval, in: 1...52)
                weekdayGrid
            }
        case .monthly:
            Section("Monthly") {
                Stepper("Every \(interval) month\(interval == 1 ? "" : "s")", value: $interval, in: 1...24)
                monthlyPatternPicker
            }
        case .yearly:
            Section("Yearly") {
                Picker("Month", selection: $yearlyMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Self.monthName(month)).tag(month)
                    }
                }
                monthlyPatternPicker
            }
        }
    }

    private var weekdayGrid: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                Button {
                    if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
                } label: {
                    Text(Self.shortLabel(day))
                        .font(Typo.ui(12, .bold))
                        .frame(width: 32, height: 32)
                        .background(
                            selectedDays.contains(day) ? Palette.accent.background : Palette.fill,
                            in: .circle
                        )
                        .foregroundStyle(selectedDays.contains(day) ? .white : Palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.fullLabel(day))
                .accessibilityAddTraits(selectedDays.contains(day) ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var monthlyPatternPicker: some View {
        Group {
            Picker("Pattern", selection: $patternKind) {
                Text("Day of month").tag(PatternKind.dayOfMonth)
                Text("Relative weekday").tag(PatternKind.relativeWeekday)
            }
            .pickerStyle(.segmented)
            if patternKind == .dayOfMonth {
                Stepper("Day \(patternDay)", value: $patternDay, in: 1...31)
            } else {
                Picker("The", selection: $patternOrdinal) {
                    Text("First").tag(WeekdayOrdinal.first)
                    Text("Second").tag(WeekdayOrdinal.second)
                    Text("Third").tag(WeekdayOrdinal.third)
                    Text("Fourth").tag(WeekdayOrdinal.fourth)
                    Text("Last").tag(WeekdayOrdinal.last)
                }
                Picker("Weekday", selection: $patternWeekday) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Text(Self.fullLabel(day)).tag(day)
                    }
                }
            }
        }
    }

    private var builtFrequency: RecurrenceFrequency {
        switch frequencyKind {
        case .daily:
            return .daily(interval: interval, everyWeekday: everyWeekdayOnly)
        case .weekly:
            return .weekly(interval: interval, days: selectedDays)
        case .monthly:
            return .monthly(interval: interval, pattern: builtPattern)
        case .yearly:
            return .yearly(month: yearlyMonth, pattern: builtPattern)
        }
    }

    private var builtPattern: MonthlyPattern {
        patternKind == .dayOfMonth ? .dayOfMonth(patternDay) : .relativeWeekday(patternOrdinal, patternWeekday)
    }

    private var builtEnd: RecurrenceEnd {
        switch endKind {
        case .never: return .never
        case .afterOccurrences: return .afterOccurrences(endOccurrences)
        case .onDate: return .onDate(endDate)
        }
    }

    private static func ordinal(ofWeekday date: Date, calendar: Calendar) -> WeekdayOrdinal {
        let weekOfMonth = calendar.component(.weekOfMonth, from: date)
        guard let range = calendar.range(of: .weekOfMonth, in: .month, for: date) else { return .first }
        if weekOfMonth >= range.upperBound - 1 { return .last }
        switch weekOfMonth {
        case 1: return .first
        case 2: return .second
        case 3: return .third
        default: return .fourth
        }
    }

    private static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[safe: month - 1] ?? "\(month)"
    }

    private static func shortLabel(_ day: Weekday) -> String {
        switch day {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }

    private static func fullLabel(_ day: Weekday) -> String {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A one-line, Outlook-style summary ("Weekly on Mon, Wed, Fri") for the
/// "Make Event Recurring" button's label once a rule is configured
/// (NSP-158).
enum RecurrenceSummary {
    static func text(for frequency: RecurrenceFrequency) -> String {
        switch frequency {
        case .daily(let interval, let everyWeekday):
            if everyWeekday { return "Every weekday" }
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case .weekly(let interval, let days):
            let dayNames = Weekday.allCases.filter { days.contains($0) }.map(shortName)
            let prefix = interval == 1 ? "Weekly" : "Every \(interval) weeks"
            return dayNames.isEmpty ? prefix : "\(prefix) on \(dayNames.joined(separator: ", "))"
        case .monthly(let interval, let pattern):
            let prefix = interval == 1 ? "Monthly" : "Every \(interval) months"
            return "\(prefix) \(patternText(pattern))"
        case .yearly(let month, let pattern):
            let formatter = DateFormatter()
            let monthName = formatter.monthSymbols[safe: month - 1] ?? "\(month)"
            return "Yearly in \(monthName), \(patternText(pattern))"
        }
    }

    private static func patternText(_ pattern: MonthlyPattern) -> String {
        switch pattern {
        case .dayOfMonth(let day): return "on day \(day)"
        case .relativeWeekday(let ordinal, let weekday):
            return "on the \(ordinalName(ordinal)) \(fullName(weekday))"
        }
    }

    private static func ordinalName(_ ordinal: WeekdayOrdinal) -> String {
        switch ordinal {
        case .first: return "first"
        case .second: return "second"
        case .third: return "third"
        case .fourth: return "fourth"
        case .last: return "last"
        }
    }

    private static func shortName(_ day: Weekday) -> String {
        switch day {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    private static func fullName(_ day: Weekday) -> String {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}
