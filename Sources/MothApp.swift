import SwiftUI
import SwiftData

@main
struct MothApp: App {
    /// The on-device store, opened exactly as before (same models, same default location), so
    /// existing assignments and photos load untouched. If opening ever fails, the app explains
    /// that instead of crashing on every launch, and it never resets or deletes the store.
    private let store: Result<ModelContainer, Error>

    init() {
        store = Result { try ModelContainer(for: Assignment.self, AssignmentPhoto.self) }
        // System alerts and action sheets live outside SwiftUI, so give them the accent too.
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = Theme.accentUI
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                StoreErrorView(message: error.localizedDescription)
            }
        }
    }
}

private struct StoreErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Moth Couldn't Open Your Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Nothing has been changed or deleted. Close and reopen Moth to try again. If this keeps happening, check that your device has free storage.\n\n\(message)")
        }
    }
}
