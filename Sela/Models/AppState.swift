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
    var provider: (any SongProvider)?
    var hiddenSongIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenSongIDs") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(hiddenSongIDs), forKey: "hiddenSongIDs")
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

    var inProgressSongs: [Song] {
        filteredSongs.filter { $0.hasTranslation && $0.translationProgress < 1.0 }
    }

    var untranslatedSongs: [Song] {
        filteredSongs.filter { !$0.hasTranslation }
    }

    var translatedSongs: [Song] {
        filteredSongs.filter { $0.translationProgress >= 1.0 }
    }

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

    func loadSongs(from provider: any SongProvider) async {
        self.provider = provider
        songs = []
        loadedCount = 0
        totalCount = 0
        isLoading = true

        for await event in provider.loadSongs() {
            if Task.isCancelled { break }
            switch event {
            case let .started(total):
                totalCount = total
            case let .parsed(parsed, loaded):
                loadedCount = loaded
                // Match the pre-streaming filter: drop songs whose slide
                // groups are all empty (intros, countdowns, media slides).
                if parsed.slideGroups.contains(where: { !$0.slides.isEmpty }) {
                    songs.append(Song(parsed: parsed))
                }
            }
        }

        // Sort once after the stream completes. Appending in parse order
        // during load avoids mid-stream reshuffling; the sort here is a
        // single O(N log N) pass over the final list.
        songs.sort {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        restoreHiddenState()
        isLoading = false
    }

    func save(_ song: Song) async throws {
        try await provider?.save(song)
    }
}
