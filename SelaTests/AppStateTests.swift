import Foundation
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

    @Test("search filters across all libraries")
    func searchFilters() {
        let state = AppState()
        state.songs = makeSongs()
        state.searchText = "Partial"

        #expect(state.filteredSongs.count == 1)
        #expect(state.filteredSongs.first?.title == "Partial Song")
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

        #expect(state.filteredSongs.allSatisfy { $0.title != "Untranslated Song" })
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

    // MARK: - Library groups

    private func library(_ name: String) -> Library {
        Library(url: URL(fileURLWithPath: "/tmp/Libraries/\(name)", isDirectory: true))
    }

    /// One song per title, attributed to `library`.
    private func songs(_ titles: [String], in library: Library) -> [Song] {
        titles.map { title in
            let song = Song(title: title, slideGroups: [
                SlideGroup(name: "V1", slides: [
                    Slide(lines: [SlideLine(original: "A")])
                ]),
            ])
            song.libraryID = library.id
            song.libraryName = library.name
            return song
        }
    }

    @Test("libraries are listed alphabetically")
    func librariesSortedByName() {
        let state = AppState()
        state.libraries = [library("Modern"), library("Christmas"), library("Hymns")]

        #expect(state.sortedLibraries.map(\.name) == ["Christmas", "Hymns", "Modern"])
    }

    @Test("each library group holds only its own visible songs")
    func songsPerLibrary() {
        let state = AppState()
        let hymns = library("Hymns")
        let modern = library("Modern")
        state.libraries = [hymns, modern]
        state.songs = songs(["Amazing Grace", "Zion"], in: hymns) + songs(["Way Maker"], in: modern)
        state.songs[1].isHidden = true

        #expect(state.songs(in: hymns).map(\.title) == ["Amazing Grace"])
        #expect(state.songs(in: modern).map(\.title) == ["Way Maker"])
    }

    @Test("all library groups show when not searching, even empty ones")
    func emptyGroupsVisibleWithoutSearch() {
        let state = AppState()
        let hymns = library("Hymns")
        let modern = library("Modern")
        state.libraries = [hymns, modern]
        state.songs = songs(["Amazing Grace"], in: hymns)

        #expect(state.sidebarLibraries.map(\.name) == ["Hymns", "Modern"])
    }

    @Test("searching hides library groups without matches")
    func searchHidesEmptyGroups() {
        let state = AppState()
        let hymns = library("Hymns")
        let modern = library("Modern")
        state.libraries = [hymns, modern]
        state.songs = songs(["Amazing Grace"], in: hymns) + songs(["Way Maker"], in: modern)

        state.searchText = "way"
        #expect(state.sidebarLibraries.map(\.name) == ["Modern"])
        #expect(state.songs(in: modern).map(\.title) == ["Way Maker"])

        state.searchText = "nothing matches this"
        #expect(state.sidebarLibraries.isEmpty)
    }

    @Test("library groups are expanded by default and collapse state persists")
    func expansionState() {
        let state = AppState()
        // `collapsedLibraryIDs` is persisted and shared with other tests, so
        // put it back the way we found it.
        let persisted = state.collapsedLibraryIDs
        defer { state.collapsedLibraryIDs = persisted }
        let hymns = library("Collapse Test Library")
        state.collapsedLibraryIDs = persisted.subtracting([hymns.id])

        #expect(state.isLibraryExpanded(hymns))

        state.setLibrary(hymns, expanded: false)
        #expect(!state.isLibraryExpanded(hymns))
        #expect(state.collapsedLibraryIDs.contains(hymns.id))

        state.setLibrary(hymns, expanded: true)
        #expect(state.isLibraryExpanded(hymns))
        #expect(!state.collapsedLibraryIDs.contains(hymns.id))
    }

    // MARK: - Ad-hoc songs

    @Test("unregistering an ad-hoc song keeps the selection when its twin exists")
    func unregisterKeepsSelectionForLibraryTwin() {
        let state = AppState()
        // Same file, same presentation uuid: the ad-hoc copy and the library
        // song the loader produced for it share an id.
        let adHoc = Song(id: "twin", title: "Amazing Grace")
        let fromLibrary = Song(
            id: "twin",
            title: "Amazing Grace",
            libraryID: "/Libraries/Hymns",
            libraryName: "Hymns"
        )
        state.registerAdHocSong(adHoc)
        state.songs.append(fromLibrary)
        state.selectedSongID = "twin"

        state.unregisterAdHocSong(adHoc)

        // The editor must not close: the very same song is still there.
        #expect(state.selectedSongID == "twin")
        #expect(state.selectedSong === fromLibrary)
    }

    @Test("unregistering the last song with an id does clear the selection")
    func unregisterClearsSelectionWithoutTwin() {
        let state = AppState()
        let adHoc = Song(id: "only", title: "Way Maker")
        state.registerAdHocSong(adHoc)
        state.selectedSongID = "only"

        state.unregisterAdHocSong(adHoc)

        #expect(state.selectedSongID == nil)
        #expect(state.songs.isEmpty)
    }
}
