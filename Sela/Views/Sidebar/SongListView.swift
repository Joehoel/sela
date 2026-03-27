import SwiftUI

struct SongListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(appState.filteredSongs, selection: $appState.selectedSongID) { song in
            SongRowView(song: song)
        }
        .listStyle(.sidebar)
        .searchable(text: $appState.searchText, prompt: "Search songs")
        .navigationTitle("Songs")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }
}

#Preview {
    let state = AppState()
    NavigationSplitView {
        SongListView()
    } detail: {
        Text("Select a song")
    }
    .environment(state)
    .task { await state.loadSongs(from: MockSongProvider()) }
    .frame(width: 700, height: 500)
}
