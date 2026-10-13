import SwiftUI
import SwiftData

/// The main workspace. One list, three ways to look at it:
///
/// - Upcoming: everything still open, grouped by deadline (what used to be "Due Soon").
/// - Recent: every assignment grouped by the day it was assigned (what used to be "Recent").
/// - Completed: finished work grouped by the day it was finished (what used to be "Completed").
struct AssignmentsView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case upcoming, recent, completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .upcoming: return "Upcoming"
            case .recent: return "Recent"
            case .completed: return "Completed"
            }
        }
    }

    @Query(sort: \Assignment.assignedDate, order: .reverse) private var assignments: [Assignment]
    @SceneStorage("moth.assignments.scope") private var scope: Scope = .upcoming

    @Environment(\.mothNow) private var now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(CompletionLinger.self) private var linger

    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            Group {
                if assignments.isEmpty {
                    EmptyStateView(title: "No Assignments Yet",
                                   message: "Add your first assignment to start keeping track of what's due.",
                                   systemImage: "checklist",
                                   actionTitle: "Add Assignment") {
                        showingNew = true
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Assignments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AddToolbarButton { showingNew = true }
                }
            }
            .mothBackground()
            .assignmentDestination()
            .newAssignmentSheet(isPresented: $showingNew)
        }
    }

    // MARK: List

    private var list: some View {
        List {
            headerSection
            switch scope {
            case .upcoming:
                upcomingSections
            case .recent:
                recentSections
            case .completed:
                completedSections
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .readableWidth()
        .assignmentDeletion()
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                scopePicker
            }
            .listRowInsets(EdgeInsets(top: Theme.Space.xs,
                                      leading: Theme.Size.rowInset,
                                      bottom: Theme.Space.m,
                                      trailing: Theme.Size.rowInset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// Switches between the three views. A segmented control is the clearest way to do it, but
    /// segments cannot grow with very large text, so a menu takes over at accessibility sizes.
    @ViewBuilder
    private var scopePicker: some View {
        let selection = Binding<Scope>(
            get: { scope },
            set: { newValue in
                withMotion(reduceMotion) { scope = newValue }
            })
        if typeSize.isAccessibilitySize {
            Picker("Show", selection: selection) {
                ForEach(Scope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Show", selection: selection) {
                ForEach(Scope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// One quiet line that answers "what needs attention?" for the current view.
    private var summary: AttributedString {
        switch scope {
        case .upcoming:
            let digest = assignments.deadlineDigest(now: now)
            if digest.openCount == 0 {
                return metaText([MetaSegment("All caught up")])
            }
            var segments: [MetaSegment] = []
            if digest.overdue > 0 {
                segments.append(MetaSegment("\(digest.overdue) overdue", tone: .overdue))
            }
            if digest.today > 0 {
                segments.append(MetaSegment("\(digest.today) due today", tone: .today))
            }
            segments.append(MetaSegment("\(digest.openCount) open"))
            return metaText(segments)
        case .recent:
            let count = assignments.count
            let noun = count == 1 ? "1 assignment" : "\(count) assignments"
            return metaText([MetaSegment(noun), MetaSegment("by date assigned")])
        case .completed:
            let count = assignments.filter { $0.isCompleted }.count
            return metaText([MetaSegment(count == 0 ? "Nothing completed yet" : "\(count) completed")])
        }
    }

    // MARK: Upcoming

    @ViewBuilder
    private var upcomingSections: some View {
        let sections = assignments.dueSections(now: now, keeping: { linger.isLingering($0) })
        if sections.isEmpty {
            emptyRow(title: "All Caught Up",
                     message: "Nothing is waiting on you. Finished work lives under Completed.",
                     systemImage: "checkmark.circle",
                     actionTitle: "Show Completed") {
                withMotion(reduceMotion) { scope = .completed }
            }
        } else {
            ForEach(sections) { section in
                Section {
                    SectionTitle(section.title,
                                 count: section.items.count,
                                 tone: section.bucket == .overdue ? .overdue : .normal)
                        .sectionHeaderRow()
                    ForEach(section.items) { assignment in
                        AssignmentRow(assignment: assignment, context: .upcoming(section.bucket))
                    }
                }
            }
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recentSections: some View {
        ForEach(assignments.groupedByDay()) { group in
            Section {
                SectionTitle(dayLabel(group.day, now: now), count: group.items.count)
                    .sectionHeaderRow()
                ForEach(group.items) { assignment in
                    AssignmentRow(assignment: assignment, context: .recent)
                }
            }
        }
    }

    // MARK: Completed

    @ViewBuilder
    private var completedSections: some View {
        let groups = assignments.groupedByCompletionDay()
        if groups.isEmpty {
            emptyRow(title: "Nothing Completed Yet",
                     message: "Assignments you finish will be collected here.",
                     systemImage: "checkmark.circle",
                     actionTitle: nil,
                     action: nil)
        } else {
            ForEach(groups) { group in
                Section {
                    SectionTitle(dayLabel(group.day, now: now), count: group.items.count)
                        .sectionHeaderRow()
                    ForEach(group.items) { assignment in
                        AssignmentRow(assignment: assignment, context: .completed)
                    }
                }
            }
        }
    }

    // MARK: Empty rows

    private func emptyRow(title: String,
                          message: String,
                          systemImage: String,
                          actionTitle: String?,
                          action: (() -> Void)?) -> some View {
        Section {
            EmptyStateView(title: title,
                           message: message,
                           systemImage: systemImage,
                           actionTitle: actionTitle,
                           action: action)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.xxl)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
}
