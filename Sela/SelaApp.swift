import SwiftUI
import TipKit

@main
struct SelaApp: App {
    @State private var appState = AppState()
    @State private var preferences = UserPreferences()

    /// Shared references for AppleScript commands to access.
    nonisolated(unsafe) static var shared: AppState?
    nonisolated(unsafe) static var sharedPreferences: UserPreferences?

    init() {
        try? Tips.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(preferences)
                .onOpenURL { url in
                    DeepLinkHandler.handle(url, appState: appState, preferences: preferences)
                }
                .onAppear {
                    SelaApp.shared = appState
                    SelaApp.sharedPreferences = preferences
                }
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
