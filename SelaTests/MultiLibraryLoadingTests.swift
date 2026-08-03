import Foundation
@testable import Sela
import Testing

@MainActor
struct MultiLibraryLoadingTests {
    private func library(_ name: String) -> Library {
        Library(url: URL(fileURLWithPath: "/tmp/Libraries/\(name)", isDirectory: true))
    }

    /// Loads the given libraries with one stub provider per library name.
    private func load(
        _ state: AppState,
        _ libraries: [Library],
        providers: [String: StubLibraryProvider]
    ) async {
        await state.loadLibraries(libraries) { library in
            providers[library.name] ?? StubLibraryProvider(titles: [])
        }
    }

    // MARK: - Loading

    @Test("all libraries are loaded and songs carry their library attribution")
    func loadsEveryLibrary() async {
        let state = AppState()
        let hymns = library("Hymns")
        let modern = library("Modern")
        let providers = [
            "Hymns": StubLibraryProvider(titles: ["Amazing Grace"]),
            "Modern": StubLibraryProvider(titles: ["Way Maker", "Build My Life"]),
        ]

        await load(state, [hymns, modern], providers: providers)

        #expect(state.songs.count == 3)
        #expect(state.libraries.map(\.name) == ["Hymns", "Modern"])
        #expect(state.songs.first { $0.title == "Amazing Grace" }?.libraryID == hymns.id)
        #expect(state.songs.first { $0.title == "Amazing Grace" }?.libraryName == "Hymns")
        #expect(state.songs.first { $0.title == "Way Maker" }?.libraryID == modern.id)
        #expect(state.songs.first { $0.title == "Way Maker" }?.libraryName == "Modern")
        #expect(state.isLoading == false)
    }

    @Test("songs from all libraries are sorted together")
    func sortsAcrossLibraries() async {
        let state = AppState()
        let providers = [
            "Hymns": StubLibraryProvider(titles: ["Amazing Grace", "Zion"]),
            "Modern": StubLibraryProvider(titles: ["Build My Life"]),
        ]

        await load(state, [library("Hymns"), library("Modern")], providers: providers)

        #expect(state.songs.map(\.title) == ["Amazing Grace", "Build My Life", "Zion"])
    }

    @Test("progress counters aggregate over all libraries")
    func aggregatesProgress() async {
        let state = AppState()
        let providers = [
            "Hymns": StubLibraryProvider(titles: ["Amazing Grace", "Zion"]),
            "Modern": StubLibraryProvider(titles: ["Build My Life"]),
        ]

        await load(state, [library("Hymns"), library("Modern")], providers: providers)

        #expect(state.totalCount == 3)
        #expect(state.loadedCount == 3)
    }

    // MARK: - Merge behavior

    @Test("reloading replaces a library's songs without duplicating them")
    func reloadDoesNotDuplicate() async {
        let state = AppState()
        let libraries = [library("Hymns"), library("Modern")]
        let providers = [
            "Hymns": StubLibraryProvider(titles: ["Amazing Grace"]),
            "Modern": StubLibraryProvider(titles: ["Way Maker"]),
        ]

        await load(state, libraries, providers: providers)
        await load(state, libraries, providers: providers)

        #expect(state.songs.map(\.title) == ["Amazing Grace", "Way Maker"])
    }

    @Test("songs of libraries that disappeared are dropped, others survive")
    func dropsStaleLibrariesOnly() async {
        let state = AppState()
        let hymns = library("Hymns")
        let modern = library("Modern")
        let providers = [
            "Hymns": StubLibraryProvider(titles: ["Amazing Grace"]),
            "Modern": StubLibraryProvider(titles: ["Way Maker"]),
        ]

        await load(state, [hymns, modern], providers: providers)
        await load(state, [hymns], providers: providers)

        #expect(state.songs.map(\.title) == ["Amazing Grace"])
        #expect(state.songs.allSatisfy { $0.libraryID == hymns.id })
    }

    @Test("loading a library does not reset songs from other sources")
    func keepsAdHocSongs() async {
        let state = AppState()
        let adHoc = Song(title: "Ad Hoc Song")
        state.songs = [adHoc]

        await load(
            state,
            [library("Hymns")],
            providers: ["Hymns": StubLibraryProvider(titles: ["Amazing Grace"])]
        )

        #expect(state.songs.count == 2)
        #expect(state.songs.contains { $0.id == adHoc.id })
    }

    @Test("a library song replaces the ad-hoc copy of the same file")
    func libraryLoadReplacesAdHocTwin() async {
        let state = AppState()
        let hymns = library("Hymns")
        // A playlist item that resolved before the library was in: same file,
        // so the loader is about to produce a Song with the very same id.
        let adHoc = Song(
            id: "Amazing Grace",
            title: "Amazing Grace",
            filePath: URL(fileURLWithPath: "/tmp/Amazing Grace.pro")
        )
        state.registerAdHocSong(adHoc)
        state.selectedSongID = adHoc.id

        await load(state, [hymns], providers: ["Hymns": StubLibraryProvider(titles: ["Amazing Grace"])])

        // One instance, not two with the same id.
        #expect(state.songs.count == 1)
        #expect(state.songs.first?.libraryID == hymns.id)
        #expect(state.provider(for: adHoc) == nil)
        // And the selection survives, because it points at the same id.
        #expect(state.selectedSong?.libraryID == hymns.id)
    }

    @Test("finishing a load bumps the generation the playlist section watches")
    func loadBumpsGeneration() async {
        let state = AppState()
        let before = state.libraryLoadGeneration

        await load(state, [library("Hymns")], providers: ["Hymns": StubLibraryProvider(titles: ["Zion"])])

        #expect(state.libraryLoadGeneration == before + 1)
    }

    @Test("hidden state is restored for songs from every library")
    func restoresHiddenAcrossLibraries() async {
        let state = AppState()
        // `hiddenSongIDs` is persisted and shared with the other tests, so use
        // titles nobody else loads and put it back the way we found it.
        let persisted = state.hiddenSongIDs
        defer { state.hiddenSongIDs = persisted }
        state.hiddenSongIDs = persisted.union(["Hidden Modern Song"])

        await load(
            state,
            [library("Hymns"), library("Modern")],
            providers: [
                "Hymns": StubLibraryProvider(titles: ["Visible Hymn"]),
                "Modern": StubLibraryProvider(titles: ["Hidden Modern Song"]),
            ]
        )

        #expect(state.hiddenSongs.map(\.title) == ["Hidden Modern Song"])
        #expect(state.filteredSongs.map(\.title) == ["Visible Hymn"])
    }

    // MARK: - Superseded loads

    /// The root-switch race: `ContentView.task(id:)` cancels the running load
    /// and starts a new one straight away. The old invocation keeps running
    /// until its stream drains, and used to finish by clearing `isLoading` and
    /// counting its late events into the new load's counters.
    @Test("a superseded load no longer clears isLoading of the load that replaced it")
    func supersededLoadKeepsProgressOfTheNewLoad() async {
        let state = AppState()
        let old = GatedProvider()
        let new = GatedProvider()

        let first = Task { await state.loadLibraries([library("Hymns")]) { _ in old } }
        await old.waitUntilSubscribed()
        old.yield(.started(total: 40))
        old.yield(.parsed(GatedProvider.parsed(title: "Old Song"), loaded: 1))

        // The user picks another root: the new load takes over the counters.
        let second = Task { await state.loadLibraries([library("Modern")]) { _ in new } }
        await new.waitUntilSubscribed()
        new.yield(.started(total: 2))
        await Task.yield()

        // Only now does the superseded load drain and return.
        old.yield(.parsed(GatedProvider.parsed(title: "Late Song"), loaded: 2))
        old.finish()
        await first.value

        #expect(state.isLoading)
        #expect(state.totalCount == 2)
        #expect(state.loadedCount == 0)
        #expect(state.songs.contains { $0.title == "Late Song" } == false)
        #expect(state.libraries.map(\.name) == ["Modern"])

        // And the load that is actually current still finishes normally.
        new.yield(.parsed(GatedProvider.parsed(title: "Way Maker"), loaded: 1))
        new.finish()
        await second.value

        #expect(state.isLoading == false)
        #expect(state.songs.map(\.title) == ["Way Maker"])
    }

    @Test("a superseded load does not bump the generation the playlist section watches")
    func supersededLoadDoesNotBumpGeneration() async {
        let state = AppState()
        let old = GatedProvider()
        let new = GatedProvider()

        let first = Task { await state.loadLibraries([library("Hymns")]) { _ in old } }
        await old.waitUntilSubscribed()

        let second = Task { await state.loadLibraries([library("Modern")]) { _ in new } }
        await new.waitUntilSubscribed()
        let generationWhileRunning = state.libraryLoadGeneration

        old.finish()
        await first.value
        #expect(state.libraryLoadGeneration == generationWhileRunning)

        new.finish()
        await second.value
        #expect(state.libraryLoadGeneration == generationWhileRunning + 1)
    }

    // MARK: - Search and selection across libraries

    @Test("search and selection work across libraries")
    func searchAndSelectAcrossLibraries() async {
        let state = AppState()
        let modern = library("Modern")
        await load(
            state,
            [library("Hymns"), modern],
            providers: [
                "Hymns": StubLibraryProvider(titles: ["Amazing Grace"]),
                "Modern": StubLibraryProvider(titles: ["Way Maker"]),
            ]
        )

        state.searchText = "way"
        #expect(state.filteredSongs.map(\.title) == ["Way Maker"])

        state.selectedSongID = state.songs.first { $0.title == "Way Maker" }?.id
        #expect(state.selectedSong?.libraryID == modern.id)
    }

    // MARK: - Save routing

    @Test("saving routes to the provider of the song's library")
    func saveRoutesToOwningLibrary() async throws {
        let state = AppState()
        let hymnsProvider = StubLibraryProvider(titles: ["Amazing Grace"])
        let modernProvider = StubLibraryProvider(titles: ["Way Maker"])

        await load(
            state,
            [library("Hymns"), library("Modern")],
            providers: ["Hymns": hymnsProvider, "Modern": modernProvider]
        )

        let song = try #require(state.songs.first { $0.title == "Way Maker" })
        try await state.save(song)

        #expect(modernProvider.savedTitles == ["Way Maker"])
        #expect(hymnsProvider.savedTitles.isEmpty)
    }

    @Test("provider lookup returns nil for a song without a library")
    func saveIgnoresSongWithoutLibrary() async throws {
        let state = AppState()
        let provider = StubLibraryProvider(titles: ["Amazing Grace"])
        await load(state, [library("Hymns")], providers: ["Hymns": provider])

        let adHoc = Song(title: "Ad Hoc Song")
        #expect(state.provider(for: adHoc) == nil)

        try await state.save(adHoc)
        #expect(provider.savedTitles == [])
    }
}

// MARK: - Gated provider

/// Provider whose load stream stays open until the test says otherwise, so two
/// `loadLibraries` calls can genuinely overlap.
@MainActor
final class GatedProvider: SongProvider {
    private var continuation: AsyncStream<SongLoadEvent>.Continuation?

    func loadSongs() -> AsyncStream<SongLoadEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func save(_ song: Song) async throws {}

    /// Suspends until `loadLibraries` has actually opened this provider's
    /// stream — events yielded before that would go nowhere.
    func waitUntilSubscribed() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func yield(_ event: SongLoadEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
    }

    static func parsed(title: String) -> ParsedSong {
        StubLibraryProvider.parsed(title: title)
    }
}

// MARK: - Stub provider

/// Provider that emits one parsed song per title and records saves, so tests
/// can assert which library a save was routed to.
@MainActor
final class StubLibraryProvider: SongProvider {
    private let titles: [String]
    private(set) var savedTitles: [String] = []

    init(titles: [String]) {
        self.titles = titles
    }

    func loadSongs() -> AsyncStream<SongLoadEvent> {
        AsyncStream { continuation in
            continuation.yield(.started(total: titles.count))
            for (index, title) in titles.enumerated() {
                continuation.yield(.parsed(Self.parsed(title: title), loaded: index + 1))
            }
            continuation.finish()
        }
    }

    func save(_ song: Song) async throws {
        savedTitles.append(song.title)
    }

    static func parsed(title: String) -> ParsedSong {
        ParsedSong(
            id: title,
            title: title,
            author: "",
            slideGroups: [
                ParsedSlideGroup(
                    id: "\(title)-g1",
                    name: "Verse 1",
                    slides: [
                        ParsedSlide(
                            id: "\(title)-s1",
                            lines: [ParsedLine(id: "\(title)-l1", original: title, translation: "")]
                        ),
                    ]
                ),
            ],
            filePath: URL(fileURLWithPath: "/tmp/\(title).pro")
        )
    }
}
