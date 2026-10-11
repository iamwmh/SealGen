import SwiftUI

@main
struct SealGenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
