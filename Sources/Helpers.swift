import Foundation

// MARK: - Fallback text

enum Fallback {
    static let noSubject = "No Subject"
    static let noSemester = "No Semester"
    static let untitled = "Untitled"
}

extension String {
    /// The string without leading or trailing spaces and line breaks.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Calendar

extension Calendar {
    /// Whole calendar days from `start` to `end`. Negative when `end` is earlier.
    /// Comparing start-of-day values keeps this correct across DST changes.
    func dayDistance(from start: Date, to end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }
}

// MARK: - Date formatting

/// "10/9/26" – the compact form that the search field also understands.
func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).year(.twoDigits))
}

/// "Oct 9", with the year added when it differs from the current one.
func monthDay(_ date: Date, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    if sameYear {
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    return date.formatted(.dateTime.month(.abbreviated).day().year())
}

/// "Fri, Oct 9", with the year added when it differs from the current one.
func weekdayMonthDay(_ date: Date, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    if sameYear {
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
}

/// "Today", "Yesterday", or "Fri, Oct 9".
func dayLabel(_ date: Date, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String {
    if date == Date.distantPast { return "Earlier" }
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday) {
        return "Yesterday"
    }
    return weekdayMonthDay(date, now: now, calendar: calendar)
}

// MARK: - Subjects

enum SubjectKey {
    /// Trimmed, case-, diacritic- and width-insensitive. Empty for "no subject".
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// A navigation value that identifies one subject within one semester.
struct SubjectRoute: Hashable {
    let id: String          // normalized subject key; "" means "No Subject"
    let name: String        // display name
    let semester: String    // trimmed semester string
}

struct SubjectSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let semester: String
    let total: Int
    let openCount: Int
    let overdue: Int
    let nextDue: Date?

    var hasSubject: Bool { !id.isEmpty }
    var route: SubjectRoute { SubjectRoute(id: id, name: name, semester: semester) }
}

// MARK: - Semesters

enum SemesterParts {
    /// Parses "1/26" or "2/2026". Returns nil for any other text.
    static func parse(_ raw: String) -> (half: Int, year: Int)? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
        guard parts.count == 2,
              let half = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let year = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (1...9).contains(half),
              year >= 0 else { return nil }
        let fullYear = year < 100 ? 2000 + year : year
        return (half, fullYear)
    }
}

/// Sort key used to order semesters; larger is newer. Unparseable text yields 0.
func semesterKey(_ s: String) -> Int {
    guard let parts = SemesterParts.parse(s) else { return 0 }
    return parts.year * 10 + parts.half
}

enum SemesterLabel {
    /// "Semester 1 · 2026" for "1/26"; any other text is shown as typed.
    static func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Fallback.noSemester }
        guard let parts = SemesterParts.parse(trimmed) else { return trimmed }
        return "Semester \(parts.half) · \(parts.year)"
    }

    /// The friendly name, or nil when the text is not in the "1/26" form.
    static func friendlyName(_ raw: String) -> String? {
        guard let parts = SemesterParts.parse(raw) else { return nil }
        return "Semester \(parts.half) · \(parts.year)"
    }
}

extension SemesterParts {
    /// The semester that follows `raw` ("1/26" -> "2/26", "2/26" -> "1/27"), or nil when
    /// `raw` is not in the "1/26" form. Uses the same two-digit year as `Assignment.semester(for:)`.
    static func next(after raw: String) -> String? {
        guard let parts = parse(raw), parts.half <= 2 else { return nil }
        if parts.half == 1 { return "2/\(parts.year % 100)" }
        return "1/\((parts.year + 1) % 100)"
    }
}

/// Unique semesters, newest first. Ties (for free-form text) fall back to A–Z so the
/// order never changes between launches.
func sortedSemesterIDs<S: Sequence>(_ ids: S) -> [String] where S.Element == String {
    Array(Set(ids)).sorted { lhs, rhs in
        if lhs.isEmpty != rhs.isEmpty { return rhs.isEmpty }
        let left = semesterKey(lhs)
        let right = semesterKey(rhs)
        if left != right { return left > right }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}

// MARK: - Deadlines

enum DueBucket: String, CaseIterable, Hashable {
    case overdue, today, tomorrow, thisWeek, later

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "Next 7 Days"
        case .later: return "Later"
        }
    }

    static func bucket(for date: Date,
                       now: Date = .now,
                       calendar: Calendar = .autoupdatingCurrent) -> DueBucket {
        switch calendar.dayDistance(from: now, to: date) {
        case ..<0: return .overdue
        case 0: return .today
        case 1: return .tomorrow
        case 2...7: return .thisWeek
        default: return .later
        }
    }

    /// Everything due within a week, including work that is already overdue.
    var isWithinWeek: Bool { self != .later }
}

// MARK: - Grouping

struct DayGroup: Identifiable {
    let day: Date
    let items: [Assignment]
    var id: Date { day }
}

struct DueSection: Identifiable {
    let bucket: DueBucket?      // nil = no due date
    let items: [Assignment]
    var id: String { bucket?.rawValue ?? "undated" }
    var title: String { bucket?.title ?? "No Due Date" }
}

extension Assignment {
    /// Subject A–Z (work without a subject last), then title.
    static func listOrder(_ lhs: Assignment, _ rhs: Assignment) -> Bool {
        if lhs.hasSubject != rhs.hasSubject { return lhs.hasSubject }
        let bySubject = lhs.subjectName.localizedStandardCompare(rhs.subjectName)
        if bySubject != .orderedSame { return bySubject == .orderedAscending }
        return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }

    /// Earliest due day first, then subject and title. Undated work sorts last.
    static func dueOrder(_ lhs: Assignment, _ rhs: Assignment) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let left = lhs.dueDate.map { calendar.startOfDay(for: $0) } ?? Date.distantFuture
        let right = rhs.dueDate.map { calendar.startOfDay(for: $0) } ?? Date.distantFuture
        if left != right { return left < right }
        return listOrder(lhs, rhs)
    }
}

extension Collection where Element == Assignment {
    /// Newest assigned day first; within a day by subject, then title.
    func groupedByDay(calendar: Calendar = .autoupdatingCurrent) -> [DayGroup] {
        let dict = Dictionary(grouping: self) { (a: Assignment) -> Date in
            calendar.startOfDay(for: a.assignedDate)
        }
        return dict.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: (dict[day] ?? []).sorted(by: Assignment.listOrder))
        }
    }

    /// Open work only, bucketed by deadline. Completed assignments never appear here (except
    /// those `isKept` holds on to briefly, so a just-completed row can show its checkmark
    /// before leaving) and assignments without a due date are collected in a final section.
    func dueSections(now: Date = .now,
                     calendar: Calendar = .autoupdatingCurrent,
                     keeping isKept: (Assignment) -> Bool = { _ in false }) -> [DueSection] {
        var byBucket: [DueBucket: [Assignment]] = [:]
        var undated: [Assignment] = []

        for assignment in self where !assignment.isCompleted || isKept(assignment) {
            if let due = assignment.dueDate {
                let bucket = DueBucket.bucket(for: due, now: now, calendar: calendar)
                byBucket[bucket, default: []].append(assignment)
            } else {
                undated.append(assignment)
            }
        }

        var sections: [DueSection] = []
        for bucket in DueBucket.allCases {
            guard let items = byBucket[bucket], !items.isEmpty else { continue }
            sections.append(DueSection(bucket: bucket, items: items.sorted(by: Assignment.dueOrder)))
        }
        if !undated.isEmpty {
            let sortedUndated = undated.sorted { (a: Assignment, b: Assignment) -> Bool in
                if a.assignedDate != b.assignedDate { return a.assignedDate > b.assignedDate }
                return Assignment.listOrder(a, b)
            }
            sections.append(DueSection(bucket: nil, items: sortedUndated))
        }
        return sections
    }

    /// Completed work grouped by the day it was finished, newest first.
    func groupedByCompletionDay(calendar: Calendar = .autoupdatingCurrent) -> [DayGroup] {
        let done = self.filter { $0.isCompleted }
        let dict = Dictionary(grouping: done) { (a: Assignment) -> Date in
            if let finished = a.completedDate { return calendar.startOfDay(for: finished) }
            return Date.distantPast
        }
        return dict.keys.sorted(by: >).map { day in
            let items = (dict[day] ?? []).sorted { (a: Assignment, b: Assignment) -> Bool in
                (a.completedDate ?? Date.distantPast) > (b.completedDate ?? Date.distantPast)
            }
            return DayGroup(day: day, items: items)
        }
    }

    /// Open-work deadline digest for the header of the Upcoming list.
    func deadlineDigest(now: Date = .now, calendar: Calendar = .autoupdatingCurrent)
        -> (overdue: Int, today: Int, openCount: Int) {
        var overdue = 0
        var today = 0
        var openCount = 0
        for assignment in self where !assignment.isCompleted {
            openCount += 1
            guard let due = assignment.dueDate else { continue }
            switch DueBucket.bucket(for: due, now: now, calendar: calendar) {
            case .overdue: overdue += 1
            case .today: today += 1
            default: break
            }
        }
        return (overdue, today, openCount)
    }

    /// Distinct semesters, newest first.
    func semesterIDs() -> [String] {
        sortedSemesterIDs(self.map { $0.semesterID })
    }

    /// One summary per subject in the given semester: no-subject last, others A–Z.
    func subjectSummaries(in semester: String,
                          now: Date = .now,
                          calendar: Calendar = .autoupdatingCurrent) -> [SubjectSummary] {
        let startOfToday = calendar.startOfDay(for: now)
        let inSemester = self.filter { $0.semesterID == semester }
        let grouped = Dictionary(grouping: inSemester) { (a: Assignment) -> String in a.subjectID }

        var summaries: [SubjectSummary] = []
        for (key, items) in grouped {
            // The most recently assigned spelling wins, so a corrected name propagates.
            let newest = items.max { $0.assignedDate < $1.assignedDate }
            let name = newest?.subjectName ?? Fallback.noSubject
            let openItems = items.filter { !$0.isCompleted }
            let overdue = openItems.filter { ($0.dueDate ?? Date.distantFuture) < startOfToday }.count
            let nextDue = openItems.compactMap { $0.dueDate }
                .filter { calendar.startOfDay(for: $0) >= startOfToday }
                .min()
            summaries.append(SubjectSummary(id: key,
                                            name: name,
                                            semester: semester,
                                            total: items.count,
                                            openCount: openItems.count,
                                            overdue: overdue,
                                            nextDue: nextDue))
        }

        return summaries.sorted { lhs, rhs in
            if lhs.hasSubject != rhs.hasSubject { return lhs.hasSubject }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Subject names in order of first appearance, one per subject. When the collection is
    /// sorted newest first, this yields the most recently used subjects first.
    func recentSubjectNames(limit: Int = 12) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for assignment in self where assignment.hasSubject {
            let key = assignment.subjectID
            if seen.insert(key).inserted {
                names.append(assignment.subject.trimmed)
                if names.count >= limit { break }
            }
        }
        return names
    }

    /// Unique subjects across everything (for suggestions and filters), A–Z.
    func distinctSubjects() -> [SubjectOption] {
        let grouped = Dictionary(grouping: self.filter { $0.hasSubject }) { (a: Assignment) -> String in a.subjectID }
        var result: [SubjectOption] = []
        for (key, items) in grouped {
            // The most recently assigned spelling wins.
            let newest = items.max { $0.assignedDate < $1.assignedDate }
            result.append(SubjectOption(id: key, name: newest?.subjectName ?? key))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Subject options

struct SubjectOption: Identifiable, Hashable {
    let id: String      // normalized key
    let name: String    // display spelling
}

// MARK: - Due labels

struct DueInfo {
    enum Tone { case overdue, today, normal }
    let text: String
    let tone: Tone
}

extension Assignment {
    /// A short deadline label for open work: "Overdue · Oct 9", "Due today", "Due tomorrow"...
    /// Nil for completed work and for assignments without a due date.
    func dueInfo(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> DueInfo? {
        guard !isCompleted, let due = dueDate else { return nil }
        switch calendar.dayDistance(from: now, to: due) {
        case ..<0:
            return DueInfo(text: "Overdue · \(monthDay(due, now: now, calendar: calendar))", tone: .overdue)
        case 0:
            return DueInfo(text: "Due today", tone: .today)
        case 1:
            return DueInfo(text: "Due tomorrow", tone: .normal)
        case 2...7:
            return DueInfo(text: "Due \(weekdayMonthDay(due, now: now, calendar: calendar))", tone: .normal)
        default:
            return DueInfo(text: "Due \(monthDay(due, now: now, calendar: calendar))", tone: .normal)
        }
    }

    /// Spoken version of the deadline for VoiceOver, without the "·" separator.
    func spokenDue(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> String? {
        guard let info = dueInfo(now: now, calendar: calendar) else { return nil }
        return info.text.replacingOccurrences(of: " · ", with: ", ")
    }
}
