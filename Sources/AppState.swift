import SwiftUI
import SwiftData
import Observation

// MARK: - The current moment

private struct MothNowKey: EnvironmentKey {
    static let defaultValue = Date()
}

extension EnvironmentValues {
    /// "Now", as the interface should see it. `ContentView` refreshes this whenever the day,
    /// time zone, locale or system clock changes, so deadline groups ("Today", "Overdue"...)
    /// recalculate on their own instead of staying stuck on the day the app was opened.
    var mothNow: Date {
        get { self[MothNowKey.self] }
        set { self[MothNowKey.self] = newValue }
    }
}

// MARK: - Completion linger
//
// Completing an assignment from a list of open work would normally make its row vanish the
// instant it is tapped, with no feedback and no easy way back from an accidental tap. Instead,
// a row that was just toggled stays in place for a moment, showing its new state, and then
// leaves. Tapping again during that moment simply reverses the change.

@Observable
final class CompletionLinger {
    static let holdTime: TimeInterval = 1.8

    private(set) var expiries: [PersistentIdentifier: Date] = [:]

    func isLingering(_ assignment: Assignment) -> Bool {
        expiries[assignment.persistentModelID] != nil
    }

    /// Keeps `assignment` visible in the list it is in for `holdTime` seconds.
    func touch(_ assignment: Assignment) {
        expiries[assignment.persistentModelID] = Date().addingTimeInterval(Self.holdTime)
        let delay = UInt64((Self.holdTime + 0.1) * 1_000_000_000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            self?.expire()
        }
    }

    @MainActor
    private func expire() {
        let now = Date()
        let remaining = expiries.filter { $0.value > now }
        guard remaining.count != expiries.count else { return }
        withAnimation(Motion.standard) {
            expiries = remaining
        }
    }
}

/// Flips an assignment between open and completed, with the follow-through every list needs:
/// keep the row visible briefly, record or clear the completion date, and save right away so
/// the change survives the app being closed.
func toggleCompletion(of assignment: Assignment,
                      linger: CompletionLinger,
                      context: ModelContext,
                      reduceMotion: Bool) {
    let makeCompleted = !assignment.isCompleted
    linger.touch(assignment)
    withMotion(reduceMotion) {
        assignment.setCompleted(makeCompleted)
    }
    try? context.save()
}

// MARK: - Delete confirmation

private struct RequestDeleteKey: EnvironmentKey {
    static let defaultValue: (Assignment) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Asks the surrounding list to confirm, then delete, an assignment.
    var requestDelete: (Assignment) -> Void {
        get { self[RequestDeleteKey.self] }
        set { self[RequestDeleteKey.self] = newValue }
    }
}

/// Provides `requestDelete` to the rows inside a list and shows the confirmation dialog.
/// Deleting always goes through a confirmation because it also removes the photos.
private struct AssignmentDeletion: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var pending: Assignment?

    init() {}

    func body(content: Content) -> some View {
        content
            .environment(\.requestDelete, { assignment in
                pending = assignment
            })
            .confirmationDialog("Delete this assignment?",
                                isPresented: isPresented,
                                titleVisibility: .visible,
                                presenting: pending) { assignment in
                Button("Delete", role: .destructive) {
                    delete(assignment)
                }
            } message: { assignment in
                Text(message(for: assignment))
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { pending != nil },
                set: { newValue in
                    if !newValue { pending = nil }
                })
    }

    private func message(for assignment: Assignment) -> String {
        let photos = assignment.photos.count
        let extra = photos == 0 ? "" : (photos == 1 ? " and its photo" : " and its \(photos) photos")
        return "“\(assignment.displayTitle)”\(extra) will be permanently removed."
    }

    private func delete(_ assignment: Assignment) {
        context.delete(assignment)
        try? context.save()
        pending = nil
    }
}

extension View {
    /// Lets rows in this view request a confirmed deletion.
    func assignmentDeletion() -> some View {
        modifier(AssignmentDeletion())
    }

    /// Registers the screen that opens when an assignment row is tapped.
    func assignmentDestination() -> some View {
        navigationDestination(for: Assignment.self) { assignment in
            AssignmentEditor(assignment: assignment, mode: .edit)
        }
    }
}
