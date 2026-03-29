@testable import Sela
import Testing

@MainActor
struct AppStateTests {
    private func makeSongs() -> [Song] {
        [
            Song(title: "Untranslated Song", slideGroups: [
                SlideGroup(name: "V1", slides: [
                    Slide(lines: [SlideLine(original: "A")])
                ]),
            ]),
            Song(title: "Partial Song", slideGroups: [
                SlideGroup(name: "V1", slides: [
                    Slide(lines: [SlideLine(original: "A", translation: "X")]),
                    Slide(lines: [SlideLine(original: "B")]),
                ]),
            ]),
            Song(title: "Done Song", slideGroups: [
                SlideGroup(name: "V1", slides: [
                    Slide(lines: [SlideLine(original: "A", translation: "X")])
                ]),
            ]),
        ]
    }

    @Test("songs are grouped by translation status")
    func grouping() {
        let state = AppState()
        state.songs = makeSongs()

        #expect(state.untranslatedSongs.count == 1)
        #expect(state.untranslatedSongs.first?.title == "Untranslated Song")

        #expect(state.inProgressSongs.count == 1)
        #expect(state.inProgressSongs.first?.title == "Partial Song")

        #expect(state.translatedSongs.count == 1)
        #expect(state.translatedSongs.first?.title == "Done Song")
    }

    @Test("search filters across all groups")
    func searchFilters() {
        let state = AppState()
        state.songs = makeSongs()
        state.searchText = "Partial"

        #expect(state.filteredSongs.count == 1)
        #expect(state.inProgressSongs.count == 1)
        #expect(state.untranslatedSongs.isEmpty)
        #expect(state.translatedSongs.isEmpty)
    }

    @Test("selectedSong returns correct song")
    func selectedSong() {
        let state = AppState()
        let songs = makeSongs()
        state.songs = songs
        state.selectedSongID = songs[1].id

        #expect(state.selectedSong?.title == "Partial Song")
    }

    @Test("selectedSong is nil when no selection")
    func noSelection() {
        let state = AppState()
        state.songs = makeSongs()

        #expect(state.selectedSong == nil)
    }

    // MARK: - Hidden songs

    @Test("hidden songs are excluded from category lists")
    func hiddenSongsExcluded() {
        let state = AppState()
        state.songs = makeSongs()
        state.songs[0].isHidden = true

        #expect(state.untranslatedSongs.isEmpty)
        #expect(state.hiddenSongs.count == 1)
        #expect(state.hiddenSongs.first?.title == "Untranslated Song")
    }

    @Test("hiddenSongs returns only hidden songs")
    func hiddenSongsList() {
        let state = AppState()
        state.songs = makeSongs()

        #expect(state.hiddenSongs.isEmpty)

        state.songs[1].isHidden = true
        #expect(state.hiddenSongs.count == 1)
        #expect(state.hiddenSongs.first?.title == "Partial Song")
    }

    @Test("hidden song IDs persist via hiddenSongIDs")
    func hiddenSongPersistence() {
        let state = AppState()
        state.songs = makeSongs()

        state.hideSong(state.songs[0])
        #expect(state.hiddenSongIDs.contains(state.songs[0].id))

        state.showSong(state.songs[0])
        #expect(!state.hiddenSongIDs.contains(state.songs[0].id))
    }

    @Test("restoreHiddenState applies persisted IDs to loaded songs")
    func restoreHiddenState() {
        let state = AppState()
        let songs = makeSongs()

        // Simulate: persist an ID before songs load
        state.hiddenSongIDs.insert(songs[2].id)
        state.songs = songs
        state.restoreHiddenState()

        #expect(state.songs[2].isHidden)
        #expect(!state.songs[0].isHidden)
        #expect(!state.songs[1].isHidden)
    }
}
