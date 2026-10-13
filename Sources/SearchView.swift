import SwiftUI
import SwiftData

/// Search and filtering. Everything the original Search tab could do is still here:
///
/// - text search through titles, subjects and notes, plus the assigned date ("10/9/26")
/// - filter by subject
/// - filter by the date an assignment was assigned
/// - filter by status: all, open or done
/// - filter for open work due within 7 days (overdue work included)
/// - a live result count
///
/// The filters are a row of compact chips instead of a form, so the results get the screen.
/// Active chips are highlighted, and "Clear" resets every filter at once.
struct SearchView: View {
    enum Status: String, CaseIterable, Identifiable {
        case all = "All"
        case open = "Open"
        case done = "Done"

        var id: String { rawValue }
    }

    @Query(sort: \Assignment.assignedDate, order: .reverse) private var assignments: [Assignment]

    @Environment(\.mothNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CompletionLinger.self) private var linger

    @State private var text = ""
    @State private var subjectKey: String?      // nil = any subject, "" = assignments without one
    @State private var assignedOn: Date?        // nil = any date
    @State private var status: Status = .all
    @State private var dueSoonOnly = false
    @State private var showingDateSheet = false
    @State private var showingNew = false

    // MARK: Filtering

    private var query: String { text.trimmed }

    private var hasFilters: Bool {
        subjectKey != nil || assignedOn != nil || status != .all || dueSoonOnly
    }

    private var isFiltering: Bool { hasFilters || !query.isEmpty }

    private func results() -> [Assignment] {
        let calendar = Calendar.autoupdatingCurrent
        let q = query

        return assignments.filter { a in
            if let key = subjectKey, a.subjectID != key { return false }
            if let day = assignedOn, !calendar.isDate(a.assignedDate, inSameDayAs: day) { return false }

            // A row that was just completed stays visible for a moment, like everywhere else.
            let stillOpen = !a.isCompleted || linger.isLingering(a)
            switch status {
            case .open where !stillOpen: return false
            case .done where !a.isCompleted: return false
            default: break
            }

            if dueSoonOnly {
                guard let due = a.dueDate, stillOpen,
                      DueBucket.bucket(for: due, now: now, calendar: calendar).isWithinWeek else {
                    return false
                }
            }

            if q.isEmpty { return true }
            return a.title.localizedStandardContains(q)
                || a.subject.localizedStandardContains(q)
                || a.notes.localizedStandardContains(q)
                || shortDate(a.assignedDate).contains(q)      // type "10/9/26" to find that day
        }
    }

    private func clearFilters() {
        withMotion(reduceMotion) {
            subjectKey = nil
            assignedOn = nil
            status = .all
            dueSoonOnly = false
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        AddToolbarButton { showingNew = true }
                    }
                }
                .searchable(text: $text,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Title, subject, notes, or date (10/9/26)")
                .assignmentDestination()
                .newAssignmentSheet(isPresented: $showingNew)
                .sheet(isPresented: $showingDateSheet) {
                    DateFilterSheet(selection: $assignedOn)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let found = results()
        if assignments.isEmpty {
            EmptyStateView(title: "Nothing to Search Yet",
                           message: "Assignments you add can be found by title, subject, notes or date.",
                           systemImage: "magnifyingglass",
                           actionTitle: "Add Assignment") {
                showingNew = true
            }
            .mothBackground()
        } else {
            List {
                if found.isEmpty {
                    noResultsSection
                } else {
                    Section {
                        resultsHeader(count: found.count)
                            .sectionHeaderRow(topSpacing: Theme.Space.s)
                        ForEach(found) { assignment in
                            AssignmentRow(assignment: assignment, context: .search)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .readableWidth()
            .mothBackground()
            .assignmentDeletion()
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func resultsHeader(count: Int) -> some View {
        if isFiltering {
            SectionTitle(count == 1 ? "1 result" : "\(count) results")
        } else {
            SectionTitle("All Assignments", count: count)
        }
    }

    /// Distinguishes "your search found nothing" from "the filters leave nothing".
    private var noResultsSection: some View {
        Section {
            Group {
                if !query.isEmpty && !hasFilters {
                    ContentUnavailableView.search(text: query)
                } else {
                    EmptyStateView(title: "No Matching Assignments",
                                   message: query.isEmpty
                                       ? "Nothing fits the filters you've chosen."
                                       : "Nothing matches “\(query)” with these filters.",
                                   systemImage: "line.3.horizontal.decrease.circle",
                                   actionTitle: "Clear Filters") {
                        clearFilters()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.xxl)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Filter chips

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                statusChip
                subjectChip
                dateChip
                dueChip
                if hasFilters {
                    clearChip
                }
            }
            .padding(.horizontal, Theme.Size.rowInset)
        }
        .scrollingBarBackground()
    }

    private var statusChip: some View {
        Menu {
            Picker("Status", selection: $status) {
                ForEach(Status.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            FilterChip(status == .all ? "Status" : status.rawValue,
                       isActive: status != .all,
                       showsChevron: true)
        }
        .accessibilityLabel("Status")
        .accessibilityValue(status.rawValue)
    }

    private var subjectChip: some View {
        let options = assignments.distinctSubjects()
        let hasUnsubjected = assignments.contains { !$0.hasSubject }
        return Menu {
            Picker("Subject", selection: $subjectKey) {
                Text("Any Subject").tag(String?.none)
                ForEach(options) { option in
                    Text(option.name).tag(String?.some(option.id))
                }
                if hasUnsubjected {
                    Text(Fallback.noSubject).tag(String?.some(""))
                }
            }
        } label: {
            FilterChip(subjectTitle(options),
                       isActive: subjectKey != nil,
                       showsChevron: true)
        }
        .accessibilityLabel("Subject")
        .accessibilityValue(subjectTitle(options))
    }

    private func subjectTitle(_ options: [SubjectOption]) -> String {
        guard let key = subjectKey else { return "Subject" }
        if key.isEmpty { return Fallback.noSubject }
        return options.first(where: { $0.id == key })?.name ?? "Subject"
    }

    private var dateChip: some View {
        Button {
            showingDateSheet = true
        } label: {
            FilterChip(dateTitle, systemImage: "calendar", isActive: assignedOn != nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date assigned")
        .accessibilityValue(assignedOn.map { monthDay($0, now: now) } ?? "Any")
    }

    private var dateTitle: String {
        guard let day = assignedOn else { return "Date Assigned" }
        return "Assigned \(monthDay(day, now: now))"
    }

    private var dueChip: some View {
        Button {
            withMotion(reduceMotion) { dueSoonOnly.toggle() }
        } label: {
            FilterChip("Due in 7 Days",
                       systemImage: dueSoonOnly ? "checkmark" : nil,
                       isActive: dueSoonOnly)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(dueSoonOnly ? .isSelected : [])
    }

    private var clearChip: some View {
        Button {
            clearFilters()
        } label: {
            Text("Clear")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Space.s)
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear all filters")
    }
}

// MARK: - Date filter

/// Picks the day to filter by. Cancel keeps the current filter; Clear removes it.
private struct DateFilterSheet: View {
    @Binding var selection: Date?
    @State private var draft: Date
    @Environment(\.dismiss) private var dismiss

    init(selection: Binding<Date?>) {
        _selection = selection
        _draft = State(initialValue: selection.wrappedValue ?? Date.now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    DatePicker("Assigned on", selection: $draft, displayedComponents: .date)
                        .datePickerStyle(.graphical)

                    if selection != nil {
                        Button("Clear Date") {
                            selection = nil
                            dismiss()
                        }
                        .buttonStyle(MothButtonStyle(kind: .quiet))
                    }
                }
                .padding(Theme.Space.l)
            }
            .mothBackground()
            .navigationTitle("Date Assigned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        selection = Calendar.autoupdatingCurrent.startOfDay(for: draft)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
