import SwiftUI
import SwiftData

// The persisted schema is intentionally identical to earlier versions of Moth,
// so existing on-device data opens without any migration.

@Model
final class Assignment {
    var title: String
    var subject: String
    var semester: String          // "1/26" = first half of 2026, "2/26" = second half
    var assignedDate: Date
    var dueDate: Date?
    var notes: String
    var isCompleted: Bool
    var completedDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \AssignmentPhoto.assignment)
    var photos: [AssignmentPhoto] = []

    init(title: String = "",
         subject: String = "",
         semester: String = Assignment.semester(for: .now),
         assignedDate: Date = .now,
         dueDate: Date? = nil,
         notes: String = "") {
        self.title = title
        self.subject = subject
        self.semester = semester
        self.assignedDate = assignedDate
        self.dueDate = dueDate
        self.notes = notes
        self.isCompleted = false
    }

    var subjectName: String {
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? Fallback.noSubject : s
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Calendar.autoupdatingCurrent.startOfDay(for: .now)
    }

    func setCompleted(_ done: Bool) {
        isCompleted = done
        completedDate = done ? .now : nil
    }

    /// "1/26" for January–June 2026, "2/26" for July–December 2026.
    /// Always uses the Gregorian calendar: on a device set to another calendar
    /// (for example the Buddhist era, where 2026 is 2569) the year would otherwise
    /// come out as "1/69" and no longer match existing data.
    static func semester(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.autoupdatingCurrent
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date) % 100
        return "\(month <= 6 ? 1 : 2)/\(year)"
    }
}

@Model
final class AssignmentPhoto {
    @Attribute(.externalStorage) var data: Data
    var assignment: Assignment?

    init(data: Data) { self.data = data }
}

// MARK: - Derived, non-persisted values

extension Assignment {
    /// Title for display. Never empty.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Fallback.untitled : trimmed
    }

    var hasSubject: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Case- and diacritic-insensitive identity, so "Math" and "math" are one subject.
    var subjectID: String { SubjectKey.normalized(subject) }

    /// Trimmed semester string used for grouping.
    var semesterID: String { semester.trimmingCharacters(in: .whitespacesAndNewlines) }
}
