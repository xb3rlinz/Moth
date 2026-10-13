import SwiftUI
import SwiftData

/// The app's three destinations. The original five tabs were views of one list of assignments,
/// so they are folded into a simpler structure:
///
/// - Assignments: Upcoming (was Due Soon), Recent and Completed, behind one switch.
/// - Subjects: semesters and subjects (was Folders).
/// - Search: text search and filters.
struct ContentView: View {
    enum AppTab: String {
        case assignments, subjects, search
    }

    @SceneStorage("moth.tab") private var selection: AppTab = .assignments

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    @State private var now = Date.now
    @State private var linger = CompletionLinger()

    var body: some View {
        TabView(selection: $selection) {
            AssignmentsView()
                .tabItem { Label("Assignments", systemImage: "checklist") }
                .tag(AppTab.assignments)

            SubjectsView()
                .tabItem { Label("Subjects", systemImage: "books.vertical") }
                .tag(AppTab.subjects)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
        }
        .tint(Theme.accent)
        .environment(\.mothNow, now)
        .environment(linger)
        // Deadline groups depend on "today". Refresh when the day rolls over, the clock, time
        // zone or locale changes, or the app comes back to the foreground.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            now = Date.now
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            now = Date.now
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            now = Date.now
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = Date.now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date.now
            } else {
                // Leaving the foreground: make sure everything typed or changed is on disk.
                try? context.save()
            }
        }
    }
}
