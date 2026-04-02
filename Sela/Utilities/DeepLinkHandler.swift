import Foundation

extension Notification.Name {
    static let fixAllIssues = Notification.Name("fixAllIssues")
}

@MainActor
enum DeepLinkHandler {
    static func handle(_ url: URL, appState: AppState, preferences: UserPreferences) {
        guard url.scheme == "sela" else { return }

        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        switch url.host {
        case "select":
            selectSong(params: params, appState: appState)

        case "translate":
            selectSong(params: params, appState: appState)
            if let engineName = params["engine"],
               let engine = TranslationEngine(rawValue: engineName)
            {
                preferences.translationEngine = engine
            }
            appState.translationRequest = params["scope"] == "all" ? .allSlides : .emptySlides

        case "save":
            NotificationCenter.default.post(name: .saveSong, object: nil)

        case "inspect":
            appState.isInspectorPresented.toggle()

        case "search":
            appState.searchText = params["q"] ?? ""
            appState.isSearchFocused = true

        case "fix-all":
            NotificationCenter.default.post(name: .fixAllIssues, object: nil)

        default:
            break
        }
    }

    private static func selectSong(params: [String: String], appState: AppState) {
        if let title = params["title"] {
            appState.selectedSongID = appState.songs.first {
                $0.title.localizedCaseInsensitiveContains(title)
            }?.id
        } else if let id = params["id"] {
            appState.selectedSongID = id
        }
    }
}
