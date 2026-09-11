import SwiftData
import SwiftUI

@main
struct BukoApp: App {
    private let storage: Result<ModelContainer, Error> = Result {
        try ModelContainer(for: Note.self)
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Your notes couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved files have been left in place. Close Buko and try again.\n\n\(error.localizedDescription)")
                }
            }
        }
    }
}
