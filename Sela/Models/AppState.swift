import Foundation
import Observation

@Observable
class AppState {
    var songs: [Song] = []
    var selectedSongID: String?
    var isInspectorPresented = false
    var searchText = ""

    var selectedSong: Song? {
        guard let id = selectedSongID else { return nil }
        return songs.first { $0.id == id }
    }

    var filteredSongs: [Song] {
        if searchText.isEmpty { return songs }
        return songs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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

    func loadSongs(from provider: any SongProvider) async {
        songs = await provider.loadSongs()
    }
}
