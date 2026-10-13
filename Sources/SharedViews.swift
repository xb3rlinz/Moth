import SwiftUI
import SwiftData

// MARK: - Row

/// Where a row is shown. It decides which details are worth repeating on the row and which
/// the surrounding section heading already says.
enum RowContext {
    /// Inside a deadline section; the heading carries "Today", "Overdue" and so on.
    case upcoming(DueBucket?)
    /// In the date-assigned list: every assignment, open or done.
    case recent
    /// In the completed list, grouped by the day it was finished.
    case completed
    /// Inside a subject, where the subject is already the screen title.
    case subject
    /// In search results, where rows come from everywhere.
    case search
}

/// One assignment: a completion control, the title, and a single quiet line of details.
/// Tapping the circle completes it; tapping anywhere else opens it.
struct AssignmentRow: View {
    let assignment: Assignment
    let context: RowContext

    @Environment(\.mothNow) private var now
    @Environment(\.requestDelete) private var requestDelete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CompletionLinger.self) private var linger

    init(assignment: Assignment, context: RowContext = .recent) {
        self.assignment = assignment
        self.context = context
    }

    var body: some View {
        NavigationLink(value: assignment) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                CompletionButton(assignment: assignment)

                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(assignment.displayTitle)
                        .font(.mothRowTitle)
                        .foregroundStyle(assignment.isCompleted ? Color.secondary : Color.primary)
                        .lineLimit(3)
                    let line = segments
                    if !line.isEmpty {
                        Text(metaText(line))
                            .font(.mothRowMeta)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if photoCount > 0 {
                    PhotoCountBadge(count: photoCount)
                }
            }
            .padding(.vertical, Theme.Space.xxs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenDescription)
            .accessibilityAction(named: Text(assignment.isCompleted ? "Mark as not completed" : "Mark as completed")) {
                toggle()
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggle()
            } label: {
                Label(assignment.isCompleted ? "Reopen" : "Complete",
                      systemImage: assignment.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                requestDelete(assignment)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                toggle()
            } label: {
                Label(assignment.isCompleted ? "Mark as Not Completed" : "Mark as Completed",
                      systemImage: assignment.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            Button(role: .destructive) {
                requestDelete(assignment)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowInsets(EdgeInsets(top: Theme.Space.xs,
                                  leading: Theme.Size.checkRowInset,
                                  bottom: Theme.Space.xs,
                                  trailing: Theme.Space.l))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.hairline)
    }

    // MARK: Details

    private var photoCount: Int { assignment.photos.count }

    private func toggle() {
        toggleCompletion(of: assignment, linger: linger, context: modelContext, reduceMotion: reduceMotion)
    }

    /// The pieces of the single details line, in reading order.
    private var segments: [MetaSegment] {
        var out: [MetaSegment] = []

        if showsSubject, assignment.hasSubject {
            out.append(MetaSegment(assignment.subjectName))
        }
        if case .search = context {
            out.append(MetaSegment("Assigned \(monthDay(assignment.assignedDate, now: now))"))
        }

        switch context {
        case .upcoming(let bucket):
            if let due = assignment.dueDate, let bucket {
                switch bucket {
                case .overdue:
                    out.append(MetaSegment(monthDay(due, now: now), tone: .overdue))
                case .thisWeek:
                    out.append(MetaSegment(weekdayMonthDay(due, now: now)))
                case .later:
                    out.append(MetaSegment(monthDay(due, now: now)))
                case .today, .tomorrow:
                    break
                }
            }
        case .completed:
            break
        case .recent, .subject, .search:
            if assignment.isCompleted {
                if let finished = assignment.completedDate {
                    out.append(MetaSegment("Completed \(monthDay(finished, now: now))"))
                } else {
                    out.append(MetaSegment("Completed"))
                }
            } else if let info = assignment.dueInfo(now: now) {
                out.append(MetaSegment(info.text, tone: info.tone))
            }
        }
        return out
    }

    private var showsSubject: Bool {
        if case .subject = context { return false }
        return true
    }

    private var spokenDescription: String {
        var parts: [String] = [assignment.displayTitle]
        if assignment.hasSubject { parts.append(assignment.subjectName) }
        if assignment.isCompleted {
            parts.append("Completed")
        } else if let due = assignment.spokenDue(now: now) {
            parts.append(due)
        }
        if photoCount == 1 {
            parts.append("1 photo")
        } else if photoCount > 1 {
            parts.append("\(photoCount) photos")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Completion control

/// The circle at the start of a row. It has its own 44pt target and its own style, so tapping it
/// never opens the assignment and tapping the row never completes it.
struct CompletionButton: View {
    let assignment: Assignment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CompletionLinger.self) private var linger

    init(assignment: Assignment) { self.assignment = assignment }

    var body: some View {
        Button {
            toggleCompletion(of: assignment, linger: linger, context: modelContext, reduceMotion: reduceMotion)
        } label: {
            Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(assignment.isCompleted ? Theme.accent : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: assignment.isCompleted) { _, isDone in isDone }
        .accessibilityLabel(assignment.isCompleted ? "Completed" : "Not completed")
        .accessibilityHint(assignment.isCompleted ? "Marks as not completed" : "Marks as completed")
    }
}

// MARK: - New assignment

/// Starting values for a new assignment, so it begins in the context it was created from.
struct AssignmentPrefill {
    var subject: String
    var semester: String?
    var assignedDate: Date
    var dueDate: Date?

    init(subject: String = "", semester: String? = nil, assignedDate: Date = Date.now, dueDate: Date? = nil) {
        self.subject = subject
        self.semester = semester
        self.assignedDate = assignedDate
        self.dueDate = dueDate
    }
}

extension View {
    /// Presents the new-assignment editor as a sheet.
    func newAssignmentSheet(isPresented: Binding<Bool>, prefill: AssignmentPrefill = AssignmentPrefill()) -> some View {
        sheet(isPresented: isPresented) {
            NewAssignmentView(prefill: prefill)
        }
    }
}

/// The sheet's content. The draft is a brand-new model that is not inserted into the database
/// until the person taps Add, so dismissing the sheet can never leave a blank or half-finished
/// assignment behind.
struct NewAssignmentView: View {
    @State private var draft: Assignment

    init(prefill: AssignmentPrefill) {
        _draft = State(initialValue: Assignment(title: "",
                                                subject: prefill.subject,
                                                semester: prefill.semester ?? Assignment.semester(for: Date.now),
                                                assignedDate: prefill.assignedDate,
                                                dueDate: prefill.dueDate))
    }

    var body: some View {
        NavigationStack {
            AssignmentEditor(assignment: draft, mode: .create)
        }
        .presentationDragIndicator(.visible)
    }
}

/// The "+" in a navigation bar.
struct AddToolbarButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    var body: some View {
        Button(action: action) {
            Label("New Assignment", systemImage: "plus")
        }
    }
}
