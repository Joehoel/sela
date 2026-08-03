import Foundation
import Observation

@Observable @MainActor
class AppState {
    var songs: [Song] = []
    var selectedSongID: String?
    var isInspectorPresented = false
    var searchText = ""
    var isSearchFocused = false
    var translationRequest: TranslationRequest?
    var isLoading = false
    var loadedCount: Int = 0
    var totalCount: Int = 0
    /// Bumped once every time `loadLibraries` finishes. Anything that resolved a
    /// file path before the libraries were in — the playlist section, at a cold
    /// start — watches this to look the path up again.
    private(set) var libraryLoadGeneration = 0
    /// Libraries currently loaded, in discovery order.
    var libraries: [Library] = []
    /// Bumped by every `loadLibraries` call, so a load that was superseded — a
    /// root switch cancels the old `.task` and starts a new one — can no longer
    /// touch `isLoading`, the counters or `songs` on the newer load's behalf.
    @ObservationIgnored private var loadGeneration = 0
    /// One provider per library, keyed by `Library.id`, so a save lands in the
    /// library the song came from.
    @ObservationIgnored private var providers: [String: any SongProvider] = [:]
    /// Providers for songs that live outside the configured libraries — playlist
    /// items whose `.pro` file sits somewhere else — keyed by song id.
    @ObservationIgnored private var adHocProviders: [String: any SongProvider] = [:]
    var hiddenSongIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenSongIDs") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(hiddenSongIDs), forKey: "hiddenSongIDs")
        }
    }
    /// Libraries whose sidebar group the user collapsed, persisted so the
    /// sidebar comes back the way it was left.
    var collapsedLibraryIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "collapsedLibraryIDs") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(collapsedLibraryIDs), forKey: "collapsedLibraryIDs")
        }
    }

    var selectedSong: Song? {
        guard let id = selectedSongID else { return nil }
        return songs.first { $0.id == id }
    }

    var filteredSongs: [Song] {
        let visible = songs.filter { !$0.isHidden }
        if searchText.isEmpty { return visible }
        return visible.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var hiddenSongs: [Song] {
        songs.filter(\.isHidden)
    }

    // MARK: - Library groups

    /// Libraries in alphabetical order — the order the sidebar shows them in.
    var sortedLibraries: [Library] {
        libraries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The library groups the sidebar renders: while searching, libraries
    /// without matches are left out.
    var sidebarLibraries: [Library] {
        guard !searchText.isEmpty else { return sortedLibraries }
        return sortedLibraries.filter { !songs(in: $0).isEmpty }
    }

    /// Visible (non-hidden) songs of one library, matching the current search.
    func songs(in library: Library) -> [Song] {
        filteredSongs.filter { $0.libraryID == library.id }
    }

    func isLibraryExpanded(_ library: Library) -> Bool {
        !collapsedLibraryIDs.contains(library.id)
    }

    func setLibrary(_ library: Library, expanded: Bool) {
        if expanded {
            collapsedLibraryIDs.remove(library.id)
        } else {
            collapsedLibraryIDs.insert(library.id)
        }
    }

    // MARK: - Hidden songs

    func hideSong(_ song: Song) {
        song.isHidden = true
        hiddenSongIDs.insert(song.id)
        if selectedSongID == song.id {
            selectedSongID = nil
        }
    }

    func showSong(_ song: Song) {
        song.isHidden = false
        hiddenSongIDs.remove(song.id)
    }

    func restoreHiddenState() {
        for song in songs where hiddenSongIDs.contains(song.id) {
            song.isHidden = true
        }
    }

    /// Loads every library in parallel and merges the results into `songs`.
    ///
    /// Merging rather than resetting: songs of libraries that are no longer
    /// present are dropped, songs loaded ad hoc (no `libraryID`) are kept, and
    /// each library replaces only its own songs. The progress counters
    /// aggregate over all libraries.
    ///
    /// - Parameter makeProvider: provider factory, injectable for tests
    ///   (same idiom as the transport closures in the translation backends).
    func loadLibraries(
        _ libraries: [Library],
        makeProvider: @MainActor (Library) -> any SongProvider = {
            ProPresenterSongProvider(libraryURL: $0.url)
        }
    ) async {
        loadGeneration += 1
        let generation = loadGeneration
        self.libraries = libraries
        providers = Dictionary(
            libraries.map { ($0.id, makeProvider($0)) },
            uniquingKeysWith: { _, latest in latest }
        )

        let knownIDs = Set(libraries.map(\.id))
        songs.removeAll { song in
            guard let libraryID = song.libraryID else { return false }
            return !knownIDs.contains(libraryID)
        }

        loadedCount = 0
        totalCount = 0
        isLoading = true

        await withTaskGroup(of: Void.self) { group in
            for library in libraries {
                group.addTask { await self.load(library, generation: generation) }
            }
        }

        // A newer load is running: it owns `isLoading` and the counters now.
        guard generation == loadGeneration else { return }
        isLoading = false
        libraryLoadGeneration += 1
    }

    /// Consumes one library's load stream, replacing that library's songs.
    private func load(_ library: Library, generation: Int) async {
        guard generation == loadGeneration, let provider = providers[library.id] else { return }
        songs.removeAll { $0.libraryID == library.id }

        for await event in provider.loadSongs() {
            if Task.isCancelled { break }
            // Events still trickling in from a superseded load would keep
            // counting up over the reset counters and re-add dropped songs.
            guard generation == loadGeneration else { return }
            switch event {
            case let .started(total):
                totalCount += total
            case let .parsed(parsed, _):
                loadedCount += 1
                // Match the pre-streaming filter: drop songs whose slide
                // groups are all empty (intros, countdowns, media slides).
                if parsed.slideGroups.contains(where: { !$0.slides.isEmpty }) {
                    let song = Song(parsed: parsed, library: library)
                    dropAdHocTwin(of: song)
                    songs.append(song)
                }
            }
        }

        guard generation == loadGeneration else { return }

        // Sort once after the stream completes. Appending in parse order
        // during load avoids mid-stream reshuffling; the sort here is a
        // single O(N log N) pass over the merged list.
        songs.sort {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        restoreHiddenState()
    }

    // MARK: - Ad-hoc songs

    /// Adds a song loaded from outside the configured libraries, so selection,
    /// the editor and saving work for it exactly like for a library song.
    ///
    /// Saving only needs the song's own file, so the default provider is scoped
    /// to the file's folder; it is injectable for tests.
    func registerAdHocSong(
        _ song: Song,
        provider: (any SongProvider)? = nil
    ) {
        if !songs.contains(where: { $0.id == song.id }) {
            songs.append(song)
        }
        if let provider {
            adHocProviders[song.id] = provider
        } else if let filePath = song.filePath {
            adHocProviders[song.id] = ProPresenterSongProvider(
                libraryURL: filePath.deletingLastPathComponent()
            )
        }
        if hiddenSongIDs.contains(song.id) {
            song.isHidden = true
        }
    }

    /// Drops an ad-hoc song again — used when the same file turns up in a real
    /// library, so the library's `Song` becomes the single instance.
    ///
    /// The selection survives when a song with the same id is still around: that
    /// is exactly the library twin taking over, and dropping the selection would
    /// close the editor on a song the user is working in.
    func unregisterAdHocSong(_ song: Song) {
        adHocProviders.removeValue(forKey: song.id)
        songs.removeAll { $0 === song }
        if selectedSongID == song.id, !songs.contains(where: { $0.id == song.id }) {
            selectedSongID = nil
        }
    }

    /// Removes the ad-hoc copy of a song a library just produced, so a `.pro`
    /// file never ends up in `songs` twice under the same id. Called while the
    /// library streams in, before the library's own `Song` is appended.
    private func dropAdHocTwin(of song: Song) {
        guard let index = songs.firstIndex(where: { $0.id == song.id && $0.libraryID == nil }) else {
            return
        }
        adHocProviders.removeValue(forKey: song.id)
        songs.remove(at: index)
    }

    /// The provider that owns `song`: the one for its library, or the ad-hoc
    /// provider it was registered with.
    func provider(for song: Song) -> (any SongProvider)? {
        guard let libraryID = song.libraryID else { return adHocProviders[song.id] }
        return providers[libraryID]
    }

    func save(_ song: Song) async throws {
        try await provider(for: song)?.save(song)
    }
}
