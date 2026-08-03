import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SongListView()
        } detail: {
            if let song = appState.selectedSong {
                SongEditorView(song: song)
                    .id(song.id)
            } else {
                ContentUnavailableView(
                    "Select a Song",
                    systemImage: "music.note.list",
                    description: Text("Choose a song from the sidebar to start translating.")
                )
            }
        }
        .searchable(text: $appState.searchText, isPresented: $appState.isSearchFocused, placement: .sidebar, prompt: "Search songs")
        .task(id: preferences.librariesRootPath) {
            let root = BookmarkManager.resolveBookmark()
                ?? URL(fileURLWithPath: (preferences.librariesRootPath as NSString).expandingTildeInPath)
            _ = root.startAccessingSecurityScopedResource()
            var urls = await LibraryDiscovery.librariesOffMain(in: root)
            // The detached scan is not cancelled with this task, so re-check:
            // after a root switch the superseded scan must not go on to load
            // its libraries over the ones the new task is loading.
            guard !Task.isCancelled else { return }
            #if DEBUG
            // No real ProPresenter library on this machine? Fall back to a
            // writable copy of the test fixtures so the app is usable in dev.
            if DevLibrary.shouldUseFixtures(realLibraryURL: urls.first ?? root) {
                urls = [DevLibrary.seededLibraryURL()]
            }
            #endif
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
            }
            await appState.loadLibraries(urls.map(Library.init(url:)))
        }
    }
}

#Preview {
    let appState = AppState()
    let preferences = UserPreferences()
    let connection = ProPresenterConnection(preferences: preferences)
    return ContentView()
        .environment(appState)
        .environment(preferences)
        .environment(connection)
        .environment(PlaylistController(appState: appState, connection: connection))
        .frame(width: 900, height: 600)
}
