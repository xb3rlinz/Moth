import SwiftUI
import SwiftData

/// The assignment screen, in two modes:
///
/// - `.create`: shown in a sheet. The assignment is a draft that is not in the database yet.
///   "Add" saves it; "Cancel" discards it (after asking, if anything was entered). Nothing is
///   written until Add succeeds, so an abandoned draft can never persist.
/// - `.edit`: pushed from a list. Changes are written as they are made, so nothing is lost.
struct AssignmentEditor: View {
    enum Mode { case create, edit }

    private enum Field: Hashable { case title, subject, semester, notes }

    /// The values a draft started with, used to tell whether the person entered anything.
    private struct Snapshot: Equatable {
        var title: String
        var subject: String
        var semester: String
        var assignedDate: Date
        var dueDate: Date?
        var notes: String
        var isCompleted: Bool

        init(_ assignment: Assignment) {
            title = assignment.title
            subject = assignment.subject
            semester = assignment.semester
            assignedDate = assignment.assignedDate
            dueDate = assignment.dueDate
            notes = assignment.notes
            isCompleted = assignment.isCompleted
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Assignment.assignedDate, order: .reverse) private var all: [Assignment]

    @Bindable var assignment: Assignment
    let mode: Mode

    @FocusState private var focus: Field?
    @State private var initial: Snapshot
    @State private var isImportingPhotos = false
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var saveError: String?

    init(assignment: Assignment, mode: Mode) {
        _assignment = Bindable(wrappedValue: assignment)
        self.mode = mode
        _initial = State(initialValue: Snapshot(assignment))
    }

    private var isCreating: Bool { mode == .create }
    private var canSave: Bool { !assignment.title.trimmed.isEmpty && !isImportingPhotos }
    private var hasChanges: Bool { Snapshot(assignment) != initial || !assignment.photos.isEmpty }

    // MARK: Body

    var body: some View {
        Form {
            titleSection
            statusSection
            detailsSection
            notesSection
            PhotoSection(assignment: assignment, isDraft: isCreating, isImporting: $isImportingPhotos)
            if !isCreating {
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
        .readableWidth()
        .mothBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isCreating ? "New Assignment" : "Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .interactiveDismissDisabled(isCreating && hasChanges)
        .confirmationDialog("Discard this assignment?",
                            isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive) { discard() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("What you've entered won't be saved.")
        }
        .alert("Couldn't Save", isPresented: saveErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task {
            // Put the cursor in the title of a new assignment once the sheet has settled.
            guard isCreating else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { focus = .title }
        }
        .onDisappear {
            if !isCreating { try? context.save() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isCreating {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }
                    .disabled(!canSave)
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    // MARK: Title and status

    private var titleSection: some View {
        Section {
            TextField("Title", text: $assignment.title, axis: .vertical)
                .font(.title3.weight(.semibold))
                .lineLimit(1...5)
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onChange(of: assignment.title) { _, newValue in
                    handleTitleChange(newValue)
                }
        }
        .listRowBackground(Theme.surface)
    }

    /// A multi-line title field would turn Return into a line break. Titles are one line, so a
    /// trailing Return moves on to the next field instead, and pasted line breaks become spaces.
    private func handleTitleChange(_ value: String) {
        guard value.contains("\n") else { return }
        let advance = value.hasSuffix("\n")
        assignment.title = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if advance { focus = .subject }
    }

    private var statusSection: some View {
        Section {
            Button {
                withMotion(reduceMotion) {
                    assignment.setCompleted(!assignment.isCompleted)
                }
                if !isCreating { try? context.save() }
            } label: {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(assignment.isCompleted ? Theme.accent : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(assignment.isCompleted ? "Completed" : "Mark as Completed")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.primary)
                        if assignment.isCompleted, let finished = assignment.completedDate {
                            Text("Finished \(weekdayMonthDay(finished)) · Tap to reopen")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.Size.tapTarget - Theme.Space.l)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: assignment.isCompleted) { _, isDone in isDone }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Details

    private var detailsSection: some View {
        Section {
            subjectRow
            semesterRow
            DatePicker("Assigned", selection: $assignment.assignedDate, displayedComponents: .date)
            dueRows
        } header: {
            Text("Details")
        }
        .listRowBackground(Theme.surface)
    }

    private var subjectRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            LabeledContent("Subject") {
                TextField("e.g. Math", text: $assignment.subject)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .subject)
                    .submitLabel(.next)
                    .onSubmit { focus = .semester }
            }
            let options = subjectSuggestions
            if !options.isEmpty {
                SuggestionChips(items: options, hint: "Sets the subject") { name in
                    assignment.subject = name
                }
            }
        }
    }

    private var semesterRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            LabeledContent("Semester") {
                TextField("e.g. 1/26", text: $assignment.semester)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .semester)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
            }
            if let friendly = SemesterLabel.friendlyName(assignment.semester) {
                Text(friendly)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            let options = semesterSuggestions
            if !options.isEmpty {
                SuggestionChips(items: options, hint: "Sets the semester") { value in
                    assignment.semester = value
                }
            }
        }
    }

    @ViewBuilder
    private var dueRows: some View {
        Toggle("Due date", isOn: dueEnabled)
        if let due = assignment.dueDate {
            DatePicker("Due", selection: dueBinding(fallback: due), displayedComponents: .date)
            if isBeforeAssigned(due) {
                Label("This is before the assigned date.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private var dueEnabled: Binding<Bool> {
        Binding(
            get: { assignment.dueDate != nil },
            set: { enabled in
                withMotion(reduceMotion) {
                    assignment.dueDate = enabled ? (assignment.dueDate ?? defaultDueDate) : nil
                }
            })
    }

    private func dueBinding(fallback: Date) -> Binding<Date> {
        Binding(get: { assignment.dueDate ?? fallback },
                set: { assignment.dueDate = $0 })
    }

    /// Tomorrow, or the day after the assigned date if that is later.
    private var defaultDueDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        let base = max(Date.now, assignment.assignedDate)
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: base)) ?? base
    }

    private func isBeforeAssigned(_ due: Date) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: assignment.assignedDate)
    }

    // MARK: Suggestions

    /// Subjects used before, most recent first, narrowed by what has been typed.
    private var subjectSuggestions: [String] {
        let typed = assignment.subject.trimmed
        let typedKey = SubjectKey.normalized(typed)
        let names = all.recentSubjectNames(limit: 40)
        let matches = names.filter { name in
            if typed.isEmpty { return true }
            return SubjectKey.normalized(name) != typedKey && name.localizedStandardContains(typed)
        }
        return Array(matches.prefix(10))
    }

    /// The semester of the assigned date, then existing semesters, then the one after.
    private var semesterSuggestions: [String] {
        let typed = assignment.semester.trimmed
        let current = Assignment.semester(for: assignment.assignedDate)
        var candidates: [String] = [current]
        candidates.append(contentsOf: all.semesterIDs())
        if let next = SemesterParts.next(after: current) { candidates.append(next) }

        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates where !candidate.isEmpty && candidate != typed {
            if seen.insert(candidate).inserted { result.append(candidate) }
            if result.count == 6 { break }
        }
        return result
    }

    // MARK: Notes

    private var notesSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if assignment.notes.isEmpty {
                    Text("Add notes, links, or reminders")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $assignment.notes)
                    .focused($focus, equals: .notes)
                    .scrollContentBackground(.hidden)
                    .lineSpacing(2)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Notes")
            }
        } header: {
            Text("Notes")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Assignment", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .confirmationDialog("Delete this assignment?",
                                isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete Assignment", role: .destructive) { deleteAssignment() }
            } message: {
                Text(deleteMessage)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var deleteMessage: String {
        let photos = assignment.photos.count
        let extra = photos == 0 ? "" : (photos == 1 ? " and its photo" : " and its \(photos) photos")
        return "“\(assignment.displayTitle)”\(extra) will be permanently removed. This can't be undone."
    }

    /// Leaves this screen first, then deletes. Removing a record while its own screen is still
    /// showing it is a classic source of crashes, so the screen is gone before the data is.
    private func deleteAssignment() {
        let target = assignment
        let deletingContext = context
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            deletingContext.delete(target)
            try? deletingContext.save()
        }
    }

    // MARK: Create actions

    private func cancel() {
        if hasChanges {
            confirmDiscard = true
        } else {
            discard()
        }
    }

    private func discard() {
        // A draft is only in the database if an earlier save attempt failed half-way.
        if assignment.modelContext != nil {
            context.delete(assignment)
        }
        dismiss()
    }

    private func save() {
        guard canSave else { return }
        assignment.title = assignment.title.trimmed
        assignment.subject = assignment.subject.trimmed
        assignment.semester = assignment.semester.trimmed
        context.insert(assignment)
        do {
            try context.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(get: { saveError != nil },
                set: { newValue in
                    if !newValue { saveError = nil }
                })
    }
}
