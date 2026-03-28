import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("libraryPath") private var libraryPath = "~/Documents/ProPresenter/Libraries/Default"

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SongListView()
        } detail: {
            if let song = appState.selectedSong {
                SongEditorView(song: song)
                    .inspector(isPresented: $appState.isInspectorPresented) {
                        DiagnoseInspector(song: song)
                            .inspectorColumnWidth(min: 200, ideal: 260, max: 340)
                    }
            } else {
                ContentUnavailableView(
                    "Select a Song",
                    systemImage: "music.note.list",
                    description: Text("Choose a song from the sidebar to start translating.")
                )
            }
        }
        .searchable(text: $appState.searchText, isPresented: $appState.isSearchFocused, placement: .sidebar, prompt: "Search songs")
        .task(id: libraryPath) {
            let url = URL(fileURLWithPath: (libraryPath as NSString).expandingTildeInPath)
            let provider = ProPresenterSongProvider(libraryURL: url)
            await appState.loadSongs(from: provider)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 900, height: 600)
}
