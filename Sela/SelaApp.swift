import SwiftUI

@main
struct SelaApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            SelaCommands(appState: appState)
        }

        Settings {
            SettingsView()
        }
    }
}
