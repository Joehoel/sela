import SwiftUI

struct SongListView: View {
    @Environment(AppState.self) private var appState
    @State private var isHiddenExpanded = false

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSongID) {
            if appState.isLoading, appState.songs.isEmpty {
                ProgressView("Loading songs…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
            if !appState.inProgressSongs.isEmpty {
                Section("In Progress") {
                    ForEach(appState.inProgressSongs) { song in
                        SongRowView(song: song)
                            .contextMenu { songContextMenu(for: song) }
                    }
                }
            }
            if !appState.untranslatedSongs.isEmpty {
                Section("Untranslated") {
                    ForEach(appState.untranslatedSongs) { song in
                        SongRowView(song: song)
                            .contextMenu { songContextMenu(for: song) }
                    }
                }
            }
            if !appState.translatedSongs.isEmpty {
                Section("Translated") {
                    ForEach(appState.translatedSongs) { song in
                        SongRowView(song: song)
                            .contextMenu { songContextMenu(for: song) }
                    }
                }
            }
            if !appState.hiddenSongs.isEmpty {
                Section("Hidden", isExpanded: $isHiddenExpanded) {
                    ForEach(appState.hiddenSongs) { song in
                        SongRowView(song: song)
                            .contextMenu { hiddenSongContextMenu(for: song) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Songs")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                .popoverTip(ChangeEngineTip())
            }
        }
    }

    private func songContextMenu(for song: Song) -> some View {
        Group {
            Button("Clear All Translations") {
                song.clearTranslations()
                Task { try? await appState.save(song) }
            }
            .disabled(!song.hasTranslation)

            Button("Hide") {
                appState.hideSong(song)
            }
        }
    }

    private func hiddenSongContextMenu(for song: Song) -> some View {
        Button("Show") {
            appState.showSong(song)
        }
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
