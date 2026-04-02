import SwiftUI
import TipKit

@main
struct SelaApp: App {
    @State private var appState = AppState()
    @State private var preferences = UserPreferences()

    init() {
        try? Tips.configure()
    }

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
