import Foundation
@testable import Sela
import Testing

/// The playlist controller, driven by `FakeProPresenter`: an in-memory route
/// table behind an injected transport, plus an injected `.pro` reader. Nothing
/// here touches the network or the disk.
@MainActor
struct PlaylistControllerTests {
    // MARK: - Fixtures

    private static let libraryPath = "/tmp/SelaTests/Libraries/Hymns"
    /// Inside a library — matches the loaded `Song` below.
    private static let gracePath = "\(libraryPath)/Amazing Grace.pro"
    /// Outside every library — has to be loaded ad hoc.
    private static let outsidePath = "/tmp/SelaTests/Elsewhere/Way Maker.pro"

    /// A ProPresenter focused on "Sunday Service" (PL1), with two presentations
    /// wired up: P1 inside a library, P2 outside every library.
    private func makeFake(items: [String] = []) -> FakeProPresenter {
        let fake = FakeProPresenter()
        fake.focused = FakeProPresenter.focusJSON(uuid: "PL1", name: "Sunday Service")
        fake.playlists["PL1"] = FakeProPresenter.playlistJSON(
            uuid: "PL1", name: "Sunday Service", items: items
        )
        fake.presentations["P1"] = FakeProPresenter.presentationJSON(uuid: "P1", path: Self.gracePath)
        fake.presentations["P2"] = FakeProPresenter.presentationJSON(uuid: "P2", path: Self.outsidePath)
        return fake
    }

    private func makeConnection(
        client: ProPresenterAPIClient? = nil
    ) -> ProPresenterConnection {
        ProPresenterConnection(
            preferences: UserPreferences(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!),
            makeClient: { _ in client },
            discover: { [] },
            wait: { _ in }
        )
    }

    private func makeController(
        appState: AppState,
        connection: ProPresenterConnection? = nil,
        reader: FakeSongReader = FakeSongReader()
    ) -> PlaylistController {
        PlaylistController(
            appState: appState,
            connection: connection ?? makeConnection(),
            readSong: { url in try reader.read(url) }
        )
    }

    /// An app state holding one song already loaded from a library.
    private func makeAppState() -> (AppState, Song) {
        let appState = AppState()
        let grace = Song(
            id: "loaded-grace",
            title: "Amazing Grace",
            filePath: URL(fileURLWithPath: Self.gracePath),
            libraryID: Self.libraryPath,
            libraryName: "Hymns"
        )
        appState.songs = [grace]
        return (appState, grace)
    }

    private static func graceItem(index: Int = 0) -> String {
        FakeProPresenter.presentationItem(index: index, name: "Amazing Grace", uuid: "P1")
    }

    private static func wayMakerItem(index: Int = 0) -> String {
        FakeProPresenter.presentationItem(index: index, name: "Way Maker", uuid: "P2")
    }

    // MARK: - Focused / active / empty

    @Test("the focused playlist is the one that gets fetched")
    func usesFocusedPlaylist() async {
        let (appState, _) = makeAppState()
        let fake = makeFake(items: [Self.graceItem()])
        let controller = makeController(appState: appState)

        await controller.refresh(using: fake.client())

        #expect(controller.status == .ready)
        #expect(controller.playlist?.id == "PL1")
        #expect(controller.playlist?.name == "Sunday Service")
        #expect(controller.playlist?.songs.map(\.title) == ["Amazing Grace"])
    }

    @Test("without a focused playlist the active one is used")
    func fallsBackToActivePlaylist() async {
        let (appState, _) = makeAppState()
        let fake = makeFake()
        // ProPresenter answers, but nothing is focused.
        fake.focused = "{}"
        fake.active = FakeProPresenter.activeJSON(uuid: "PL2", name: "Announcements")
        fake.playlists["PL2"] = FakeProPresenter.playlistJSON(
            uuid: "PL2", name: "Announcements", items: [Self.graceItem()]
        )
        let controller = makeController(appState: appState)

        await controller.refresh(using: fake.client())

        #expect(controller.playlist?.id == "PL2")
        #expect(controller.playlist?.name == "Announcements")
        #expect(controller.playlist?.songs.count == 1)
    }

    @Test("neither focused nor active leaves the playlist empty")
    func noPlaylistAtAll() async {
        let fake = makeFake()
        fake.focused = "{}"
        fake.active = "{}"
        let controller = makeController(appState: AppState())

        await controller.refresh(using: fake.client())

        #expect(controller.playlist == nil)
        #expect(controller.status == .unavailable)
    }

    // MARK: - Item mix

    @Test("headers become sections, media is skipped, presentations become songs")
    func buildsHeadersAndSkipsMedia() async {
        let (appState, _) = makeAppState()
        let fake = makeFake(items: [
            FakeProPresenter.headerItem(index: 0, name: "Songs"),
            Self.graceItem(index: 1),
            FakeProPresenter.mediaItem(index: 2, name: "Countdown"),
        ])
        let controller = makeController(appState: appState)

        await controller.refresh(using: fake.client())

        let items = controller.playlist?.items ?? []
        #expect(items.count == 2)
        #expect(items.first?.id == "header:Songs")
        #expect(items.last?.song?.title == "Amazing Grace")
    }

    // MARK: - Resolution

    @Test("a path inside a library resolves to the very same Song object")
    func matchesLoadedSong() async {
        let (appState, grace) = makeAppState()
        let fake = makeFake(items: [Self.graceItem()])
        let reader = FakeSongReader()
        let controller = makeController(appState: appState, reader: reader)

        await controller.refresh(using: fake.client())

        #expect(controller.playlist?.songs.first === grace)
        #expect(reader.readPaths.isEmpty)
        #expect(appState.songs.count == 1)
    }

    @Test("a path outside every library is loaded ad hoc and registered")
    func loadsAdHocSong() async throws {
        let (appState, _) = makeAppState()
        let fake = makeFake(items: [Self.wayMakerItem()])
        let reader = FakeSongReader(readable: [Self.outsidePath: "Way Maker"])
        let controller = makeController(appState: appState, reader: reader)

        await controller.refresh(using: fake.client())

        let song = try #require(controller.playlist?.songs.first)
        #expect(song.title == "Way Maker")
        #expect(song.libraryID == nil)
        // Registered, so `selectedSongID` navigation and the editor work.
        #expect(appState.songs.contains { $0 === song })
        appState.selectedSongID = song.id
        #expect(appState.selectedSong === song)
        // And saving routes somewhere instead of silently doing nothing.
        #expect(appState.provider(for: song) != nil)
    }

    @Test("an ad-hoc song is reused instead of reloaded on the next refresh")
    func reusesAdHocSong() async throws {
        let appState = AppState()
        let fake = makeFake(items: [Self.wayMakerItem()])
        let reader = FakeSongReader(readable: [Self.outsidePath: "Way Maker"])
        let controller = makeController(appState: appState, reader: reader)

        await controller.refresh(using: fake.client())
        let first = try #require(controller.playlist?.songs.first)
        await controller.refresh(using: fake.client())

        #expect(controller.playlist?.songs.first === first)
        #expect(reader.readPaths.count == 1)
        #expect(appState.songs.count == 1)
    }

    @Test("an unreadable or missing file skips the item instead of failing")
    func skipsUnreadableFile() async {
        let fake = makeFake(items: [
            FakeProPresenter.presentationItem(index: 0, name: "Gone", uuid: "P3"),
            Self.wayMakerItem(index: 1),
        ])
        fake.presentations["P3"] = FakeProPresenter.presentationJSON(
            uuid: "P3", path: "/tmp/SelaTests/Gone.pro"
        )
        let reader = FakeSongReader(readable: [Self.outsidePath: "Way Maker"])
        let controller = makeController(appState: AppState(), reader: reader)

        await controller.refresh(using: fake.client())

        #expect(controller.status == .ready)
        #expect(controller.playlist?.songs.map(\.title) == ["Way Maker"])
    }

    @Test("an item without a presentation path is skipped")
    func skipsItemWithoutPath() async {
        let fake = makeFake(items: [
            FakeProPresenter.presentationItem(index: 0, name: "Unlinked", uuid: "P4"),
        ])
        fake.presentations["P4"] = FakeProPresenter.presentationJSON(uuid: "P4", path: nil)
        let controller = makeController(appState: AppState())

        await controller.refresh(using: fake.client())

        #expect(controller.playlist?.items.isEmpty == true)
    }

    // MARK: - Selection

    @Test("a manually chosen playlist wins, and following restores the focused one")
    func manualSelectionAndBackToFollowing() async {
        let (appState, _) = makeAppState()
        let fake = makeFake()
        fake.playlists["PL9"] = FakeProPresenter.playlistJSON(
            uuid: "PL9", name: "Christmas Eve", items: [Self.graceItem()]
        )
        let controller = makeController(appState: appState)

        controller.select(id: "PL9", name: "Christmas Eve")
        await controller.refresh(using: fake.client())

        #expect(controller.selection == .manual(id: "PL9", name: "Christmas Eve"))
        #expect(controller.playlist?.name == "Christmas Eve")
        #expect(controller.playlist?.songs.count == 1)

        controller.followProPresenter()
        await controller.refresh(using: fake.client())

        #expect(controller.selection == .followProPresenter)
        #expect(controller.playlist?.name == "Sunday Service")
    }

    @Test("a manual playlist keeps following its own content updates")
    func manualSelectionStillWatchesContent() async {
        let fake = makeFake()
        fake.playlists["PL9"] = FakeProPresenter.playlistJSON(
            uuid: "PL9", name: "Christmas Eve", items: []
        )
        let controller = makeController(appState: AppState())
        controller.select(id: "PL9", name: "Christmas Eve")
        await controller.refresh(using: fake.client())

        fake.contentChanges = true
        let outcome = await controller.waitForChange(using: fake.client())

        #expect(outcome == .changed)
        #expect(fake.openedStreamPaths.contains { $0.contains("v1/playlist/PL9/updates") })
        // The focus stream is not used while a playlist is pinned.
        #expect(!fake.openedStreamPaths.contains { $0.contains("status/updates") })
    }

    @Test("the header menu is fed by the playlist tree, and emptied when offline")
    func loadsPlaylistTree() async throws {
        let fake = makeFake()
        fake.playlistTree = """
        [{"id":{"uuid":"G1","name":"Services","index":0},"type":"group","playlists":[\
        {"id":{"uuid":"PL1","name":"Sunday Service","index":0},"type":"playlist"}]}]
        """
        let connection = makeConnection(client: fake.client())
        await connection.connectOnce()
        let controller = makeController(appState: AppState(), connection: connection)

        await controller.loadAvailablePlaylists()

        let group = try #require(controller.availablePlaylists.first)
        #expect(group.type == .group)
        #expect(group.playlists.map(\.id.name) == ["Sunday Service"])

        connection.stop()
        await controller.loadAvailablePlaylists()

        #expect(controller.availablePlaylists.isEmpty)
    }

    // MARK: - Live updates

    @Test("a content update re-fetches and re-resolves the playlist")
    func contentUpdateTriggersReresolution() async {
        let (appState, _) = makeAppState()
        let fake = makeFake()
        // The operator drops a song into the playlist while Sela is streaming.
        fake.contentChanges = true
        fake.onContentStreamOpened = { fake in
            fake.playlists["PL1"] = FakeProPresenter.playlistJSON(
                uuid: "PL1",
                name: "Sunday Service",
                items: [FakeProPresenter.presentationItem(index: 0, name: "Amazing Grace", uuid: "P1")]
            )
        }
        let connection = makeConnection(client: fake.client())
        await connection.connectOnce()
        let controller = makeController(appState: appState, connection: connection)

        controller.start()
        defer { controller.stop() }
        let updated = await waitUntil { controller.playlist?.songs.count == 1 }

        #expect(updated)
        #expect(controller.playlist?.songs.first?.title == "Amazing Grace")
    }

    @Test("a focus update naming another playlist switches to it")
    func focusUpdateSwitchesPlaylist() async {
        let fake = makeFake()
        fake.playlists["PL2"] = FakeProPresenter.playlistJSON(
            uuid: "PL2", name: "Evening Service", items: []
        )
        let evening = FakeProPresenter.focusJSON(uuid: "PL2", name: "Evening Service")
        fake.focusUpdate = FakeProPresenter.statusUpdateJSON(url: "/v1/playlist/focused", data: evening)
        fake.onFocusStreamOpened = { $0.focused = evening }
        let controller = makeController(appState: AppState())
        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.id == "PL1")

        let outcome = await controller.waitForChange(using: fake.client())
        await controller.refresh(using: fake.client())

        #expect(outcome == .changed)
        #expect(controller.playlist?.id == "PL2")
    }

    @Test("an item-level focus update inside the same playlist is ignored")
    func focusUpdateForSamePlaylistIsIgnored() async {
        let fake = makeFake()
        // The operator clicked another song in the same playlist.
        fake.focusUpdate = FakeProPresenter.statusUpdateJSON(
            url: "/v1/playlist/focused",
            data: FakeProPresenter.focusJSON(uuid: "PL1", name: "Sunday Service")
        )
        let controller = makeController(appState: AppState())
        await controller.refresh(using: fake.client())

        // The content stream never fires here, so the ignored update leaves the
        // focus stream to run out instead of reporting a change.
        let outcome = await controller.waitForChange(using: fake.client())

        #expect(outcome == .ended)
    }

    @Test("losing the connection keeps the last known playlist")
    func offlineKeepsLastKnownPlaylist() async {
        let fake = makeFake()
        let connection = makeConnection(client: fake.client())
        await connection.connectOnce()
        let controller = makeController(appState: AppState(), connection: connection)

        controller.start()
        defer { controller.stop() }
        _ = await waitUntil { controller.status == .ready }
        connection.stop()
        let wentOffline = await waitUntil { controller.status == .offline }

        #expect(wentOffline)
        #expect(controller.playlist?.name == "Sunday Service")
    }

    // MARK: - Helpers

    /// Polls the main actor until `condition` holds, or gives up after ~2s.
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
