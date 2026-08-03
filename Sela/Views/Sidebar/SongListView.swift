import SwiftUI

struct SongListView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlaylistController.self) private var playlistController
    @State private var isHiddenExpanded = false

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSongID) {
            PlaylistSectionView()
            if appState.isLoading, appState.songs.isEmpty {
                loadingIndicator
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
            ForEach(appState.sidebarLibraries) { library in
                Section(library.name, isExpanded: expansion(for: library)) {
                    ForEach(appState.songs(in: library)) { song in
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
        // A playlist change in ProPresenter arrives on its own, without a user
        // gesture to animate from — so the list animates the row changes itself.
        .animation(.default, value: playlistController.playlist?.items.map(\.id))
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

    /// Expand/collapse binding for a library group, persisted in `AppState`.
    /// While searching the groups stay open so matches are never hidden behind
    /// a collapsed header.
    private func expansion(for library: Library) -> Binding<Bool> {
        guard appState.searchText.isEmpty else { return .constant(true) }
        return Binding(
            get: { appState.isLibraryExpanded(library) },
            set: { appState.setLibrary(library, expanded: $0) }
        )
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if appState.totalCount > 0 {
            VStack(spacing: 8) {
                ProgressView(
                    value: Double(appState.loadedCount),
                    total: Double(appState.totalCount)
                )
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
                Text("Loading \(appState.loadedCount) of \(appState.totalCount)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView("Loading songs…")
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
    let hymns = Library(url: URL(fileURLWithPath: "/Libraries/Hymns", isDirectory: true))
    let modern = Library(url: URL(fileURLWithPath: "/Libraries/Modern", isDirectory: true))
    state.libraries = [hymns, modern]
    state.songs = MockSongProvider.allSongs.enumerated().map { index, song in
        let library = index.isMultiple(of: 2) ? hymns : modern
        song.libraryID = library.id
        song.libraryName = library.name
        return song
    }
    let connection = ProPresenterConnection(preferences: UserPreferences())
    return NavigationSplitView {
        SongListView()
    } detail: {
        Text("Select a song")
    }
    .environment(state)
    .environment(connection)
    .environment(PlaylistController(appState: state, connection: connection))
    .frame(width: 700, height: 500)
}
