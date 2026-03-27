import SwiftUI

struct SongListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(appState.filteredSongs, selection: $appState.selectedSongID) { song in
            SongRowView(song: song)
        }
        .searchable(text: $appState.searchText, prompt: "Search songs")
        .navigationTitle("Songs")
    }
}
