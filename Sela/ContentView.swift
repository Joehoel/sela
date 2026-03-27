import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    private nonisolated(unsafe) let provider: any SongProvider = MockSongProvider()

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
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .task {
            await appState.loadSongs(from: provider)
        }
    }
}
