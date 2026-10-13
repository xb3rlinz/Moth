import SwiftUI
import SwiftData

// MARK: - Subjects

/// Semesters and subjects, replacing the old nested "Folders" tree.
///
/// The screen shows one semester at a time. Its subjects are a plain list; tapping a subject
/// opens that subject's assignments. There is no folder entity behind this: both semesters and
/// subjects are derived from the assignments themselves, so no new data is stored.
struct SubjectsView: View {
    @Query(sort: \Assignment.assignedDate, order: .reverse) private var assignments: [Assignment]
    @SceneStorage("moth.subjects.semester") private var storedSemester = ""

    @Environment(\.mothNow) private var now

    @State private var showingNew = false

    // MARK: Semester selection

    private var currentSemester: String { Assignment.semester(for: now) }

    /// Semesters that have assignments, newest first.
    private var semestersWithData: [String] { assignments.semesterIDs() }

    /// The same, plus the current calendar semester so a new term can be started even before
    /// it has any assignments.
    private var semesterOptions: [String] {
        let withData = semestersWithData
        if withData.contains(currentSemester) { return withData }
        return sortedSemesterIDs(withData + [currentSemester])
    }

    /// The semester on screen: the remembered one if it still exists, otherwise the current
    /// semester, otherwise the newest one that has assignments.
    private var selectedSemester: String {
        if storedSemester.hasPrefix("s:") {
            let remembered = String(storedSemester.dropFirst(2))
            if semesterOptions.contains(remembered) { return remembered }
        }
        let withData = semestersWithData
        if withData.contains(currentSemester) { return currentSemester }
        return withData.first ?? currentSemester
    }

    private var semesterBinding: Binding<String> {
        Binding(get: { selectedSemester },
                set: { newValue in storedSemester = "s:" + newValue })
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if assignments.isEmpty {
                    EmptyStateView(title: "No Subjects Yet",
                                   message: "Subjects appear here as you add assignments, organized by semester.",
                                   systemImage: "books.vertical",
                                   actionTitle: "Add Assignment") {
                        showingNew = true
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Subjects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AddToolbarButton { showingNew = true }
                }
            }
            .mothBackground()
            .navigationDestination(for: SubjectRoute.self) { route in
                SubjectDetailView(route: route)
            }
            .assignmentDestination()
            .newAssignmentSheet(isPresented: $showingNew,
                                prefill: AssignmentPrefill(semester: selectedSemester))
        }
    }

    private var list: some View {
        let semester = selectedSemester
        let summaries = assignments.subjectSummaries(in: semester, now: now)
        return List {
            Section {
                semesterHeader(semester: semester, summaries: summaries)
                    .listRowInsets(EdgeInsets(top: Theme.Space.xs,
                                              leading: Theme.Size.rowInset,
                                              bottom: Theme.Space.m,
                                              trailing: Theme.Size.rowInset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if summaries.isEmpty {
                Section {
                    EmptyStateView(title: "No Assignments This Semester",
                                   message: "Add an assignment and its subject will appear here.",
                                   systemImage: "books.vertical",
                                   actionTitle: "Add Assignment") {
                        showingNew = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xxl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(summaries) { summary in
                        NavigationLink(value: summary.route) {
                            SubjectRow(summary: summary, now: now)
                        }
                        .listRowInsets(EdgeInsets(top: Theme.Space.xs,
                                                  leading: Theme.Size.rowInset,
                                                  bottom: Theme.Space.xs,
                                                  trailing: Theme.Space.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.hairline)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .readableWidth()
    }

    // MARK: Header

    /// The semester heading doubles as the switcher: tap it to choose another semester.
    private func semesterHeader(semester: String, summaries: [SubjectSummary]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if semesterOptions.count > 1 {
                Menu {
                    Picker("Semester", selection: semesterBinding) {
                        ForEach(semesterOptions, id: \.self) { id in
                            Text(SemesterLabel.title(id)).tag(id)
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Text(SemesterLabel.title(semester))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: Theme.Size.tapTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Semester: \(SemesterLabel.title(semester))")
                .accessibilityHint("Choose a different semester")
            } else {
                Text(SemesterLabel.title(semester))
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(metaText(headerSegments(summaries)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func headerSegments(_ summaries: [SubjectSummary]) -> [MetaSegment] {
        if summaries.isEmpty { return [MetaSegment("No assignments yet")] }
        let subjectCount = summaries.filter { $0.hasSubject }.count
        let openTotal = summaries.reduce(0) { $0 + $1.openCount }
        let overdue = summaries.reduce(0) { $0 + $1.overdue }

        var segments: [MetaSegment] = []
        if subjectCount > 0 {
            segments.append(MetaSegment(subjectCount == 1 ? "1 subject" : "\(subjectCount) subjects"))
        }
        if overdue > 0 {
            segments.append(MetaSegment("\(overdue) overdue", tone: .overdue))
        }
        segments.append(MetaSegment(openTotal == 0 ? "Nothing open" : "\(openTotal) open"))
        return segments
    }
}

// MARK: - Subject row

private struct SubjectRow: View {
    let summary: SubjectSummary
    let now: Date

    init(summary: SubjectSummary, now: Date) {
        self.summary = summary
        self.now = now
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(summary.name)
                    .font(.mothRowTitle)
                    .foregroundStyle(summary.hasSubject ? Color.primary : Color.secondary)
                    .lineLimit(2)
                Text(detail)
                    .font(.mothRowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if summary.overdue > 0 {
                Text("\(summary.overdue) overdue")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.danger)
                    .fixedSize()
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDescription)
    }

    private var detail: String {
        if summary.openCount == 0 {
            return summary.total == 1 ? "1 completed" : "All \(summary.total) completed"
        }
        var parts = ["\(summary.openCount) open"]
        if let next = summary.nextDue {
            parts.append("next due \(weekdayMonthDay(next, now: now))")
        }
        return parts.joined(separator: " · ")
    }

    private var spokenDescription: String {
        var parts = [summary.name, detail]
        if summary.overdue > 0 { parts.append("\(summary.overdue) overdue") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Subject detail

/// One subject within one semester: its open and completed assignments, with a "+" that
/// starts a new assignment already filed under this subject and semester.
struct SubjectDetailView: View {
    enum Grouping: String, CaseIterable, Identifiable {
        case status, assigned

        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: return "Status"
            case .assigned: return "Date Assigned"
            }
        }
    }

    let route: SubjectRoute

    @Query(sort: \Assignment.assignedDate, order: .reverse) private var all: [Assignment]
    @Environment(\.mothNow) private var now
    @State private var grouping: Grouping = .status
    @State private var showingNew = false

    init(route: SubjectRoute) { self.route = route }

    private var items: [Assignment] {
        all.filter { $0.semesterID == route.semester && $0.subjectID == route.id }
    }

    var body: some View {
        let items = self.items
        List {
            Section {
                Text(metaText(summarySegments(items)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: Theme.Space.xs,
                                              leading: Theme.Size.rowInset,
                                              bottom: Theme.Space.m,
                                              trailing: Theme.Size.rowInset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if items.isEmpty {
                Section {
                    EmptyStateView(title: "No Assignments",
                                   message: "Nothing is filed under this subject right now.",
                                   systemImage: "tray",
                                   actionTitle: "Add Assignment") {
                        showingNew = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xxl)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                switch grouping {
                case .status:
                    statusSections(items)
                case .assigned:
                    assignedSections(items)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .readableWidth()
        .mothBackground()
        .assignmentDeletion()
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Group By", selection: $grouping) {
                        ForEach(Grouping.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label("Group By", systemImage: "line.3.horizontal.decrease")
                }
                AddToolbarButton { showingNew = true }
            }
        }
        .newAssignmentSheet(isPresented: $showingNew,
                            prefill: AssignmentPrefill(subject: route.id.isEmpty ? "" : route.name,
                                                       semester: route.semester))
    }

    private func summarySegments(_ items: [Assignment]) -> [MetaSegment] {
        var segments: [MetaSegment] = [MetaSegment(SemesterLabel.title(route.semester))]
        if items.isEmpty { return segments }
        let digest = items.deadlineDigest(now: now)
        if digest.overdue > 0 {
            segments.append(MetaSegment("\(digest.overdue) overdue", tone: .overdue))
        }
        segments.append(MetaSegment(digest.openCount == 0 ? "Nothing open" : "\(digest.openCount) open"))
        return segments
    }

    @ViewBuilder
    private func statusSections(_ items: [Assignment]) -> some View {
        let openItems = items.filter { !$0.isCompleted }.sorted(by: Assignment.dueOrder)
        let done = items.filter { $0.isCompleted }.sorted { (lhs: Assignment, rhs: Assignment) -> Bool in
            (lhs.completedDate ?? Date.distantPast) > (rhs.completedDate ?? Date.distantPast)
        }
        if !openItems.isEmpty {
            Section {
                SectionTitle("Open", count: openItems.count)
                    .sectionHeaderRow(topSpacing: Theme.Space.s)
                ForEach(openItems) { assignment in
                    AssignmentRow(assignment: assignment, context: .subject)
                }
            }
        }
        if !done.isEmpty {
            Section {
                SectionTitle("Completed", count: done.count)
                    .sectionHeaderRow()
                ForEach(done) { assignment in
                    AssignmentRow(assignment: assignment, context: .subject)
                }
            }
        }
    }

    @ViewBuilder
    private func assignedSections(_ items: [Assignment]) -> some View {
        ForEach(items.groupedByDay()) { group in
            Section {
                SectionTitle(dayLabel(group.day, now: now), count: group.items.count)
                    .sectionHeaderRow()
                ForEach(group.items) { assignment in
                    AssignmentRow(assignment: assignment, context: .subject)
                }
            }
        }
    }
}
