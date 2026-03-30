import SwiftUI

@main
struct SelaApp: App {
    @State private var appState = AppState()
    @State private var preferences = UserPreferences()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(preferences)
        }
        .commands {
            SelaCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(preferences)
        }
    }
}
