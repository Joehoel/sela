import SwiftUI
import TipKit

@main
struct SelaApp: App {
    @State private var appState: AppState
    @State private var preferences: UserPreferences
    @State private var connection: ProPresenterConnection
    @State private var playlistController: PlaylistController

    /// Shared references for AppleScript commands to access.
    nonisolated(unsafe) static var shared: AppState?
    nonisolated(unsafe) static var sharedPreferences: UserPreferences?

    init() {
        let preferences = UserPreferences()
        let appState = AppState()
        let connection = ProPresenterConnection(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _appState = State(initialValue: appState)
        _connection = State(initialValue: connection)
        _playlistController = State(
            initialValue: PlaylistController(appState: appState, connection: connection)
        )

        SentryConfig.start()
        SelaMetrics.appLaunched()
        try? Tips.configure()
    }

    /// Runs `start` unless the app is only hosting a test bundle.
    ///
    /// `xcodebuild test` launches this app as the test host, so `onAppear` would
    /// otherwise open the real ProPresenter loops: Bonjour browsing, connect
    /// attempts to whatever ProPresenter happens to run on the machine, the
    /// local-network prompt, and `proPresenterLastKnownEndpoint` written into
    /// the developer's own defaults.
    static func startLiveServices(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        testCaseClass: AnyClass? = NSClassFromString("XCTestCase"),
        start: () -> Void
    ) {
        guard environment["XCTestConfigurationFilePath"] == nil, testCaseClass == nil else { return }
        start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(preferences)
                .environment(connection)
                .environment(playlistController)
                .onOpenURL { url in
                    DeepLinkHandler.handle(url, appState: appState, preferences: preferences)
                }
                .onAppear {
                    SelaApp.shared = appState
                    SelaApp.sharedPreferences = preferences
                    SelaApp.startLiveServices {
                        connection.start()
                        playlistController.start()
                    }
                }
        }
        .commands {
            SelaCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(preferences)
                .environment(connection)
        }
    }
}
