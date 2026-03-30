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
        .task(id: preferences.libraryPath) {
            let url = BookmarkManager.resolveBookmark()
                ?? URL(fileURLWithPath: (preferences.libraryPath as NSString).expandingTildeInPath)
            _ = url.startAccessingSecurityScopedResource()
            let provider = ProPresenterSongProvider(libraryURL: url)
            await appState.loadSongs(from: provider)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(UserPreferences())
        .frame(width: 900, height: 600)
}
