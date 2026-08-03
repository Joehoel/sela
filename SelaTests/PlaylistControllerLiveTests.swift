import Foundation
@testable import Sela
import Testing

/// The parts of `PlaylistController` that only show up over time: the race with
/// the library load, a refresh that is cancelled halfway, the damping that keeps
/// a dead update stream from turning into a hot loop, and which ProPresenter
/// updates count as a focus change at all.
///
/// Same setup as `PlaylistControllerTests`: an in-memory ProPresenter behind an
/// injected transport and an injected `.pro` reader.
@MainActor
struct PlaylistControllerLiveTests {
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

    private func makeConnection() -> ProPresenterConnection {
        ProPresenterConnection(
            preferences: UserPreferences(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!),
            makeClient: { _ in nil },
            discover: { [] },
            wait: { _ in }
        )
    }

    private func makeController(
        appState: AppState,
        reader: FakeSongReader = FakeSongReader()
    ) -> PlaylistController {
        PlaylistController(
            appState: appState,
            connection: makeConnection(),
            readSong: { url in try reader.read(url) }
        )
    }

    /// An app state holding one song already loaded from a library.
    private func makeAppState() -> AppState {
        let appState = AppState()
        appState.songs = [
            Song(
                id: "loaded-grace",
                title: "Amazing Grace",
                filePath: URL(fileURLWithPath: Self.gracePath),
                libraryID: Self.libraryPath,
                libraryName: "Hymns"
            ),
        ]
        return appState
    }

    private static func graceItem(index: Int = 0) -> String {
        FakeProPresenter.presentationItem(index: index, name: "Amazing Grace", uuid: "P1")
    }

    private static func wayMakerItem(index: Int = 0) -> String {
        FakeProPresenter.presentationItem(index: index, name: "Way Maker", uuid: "P2")
    }

    @Test("items the operator hid in ProPresenter are left out")
    func skipsHiddenItems() async {
        let appState = makeAppState()
        let fake = makeFake(items: [
            Self.graceItem(index: 0),
            FakeProPresenter.presentationItem(index: 1, name: "Way Maker", uuid: "P2", isHidden: true),
        ])
        let reader = FakeSongReader(readable: [Self.outsidePath: "Way Maker"])
        let controller = makeController(appState: appState, reader: reader)

        await controller.refresh(using: fake.client())

        #expect(controller.playlist?.songs.map(\.title) == ["Amazing Grace"])
        // A hidden item is not even resolved.
        #expect(reader.readPaths.isEmpty)
    }

    // MARK: - Library race

    @Test("a playlist resolved before the libraries loaded collapses onto the library Song")
    func adHocSongCollapsesOntoLibrarySong() async throws {
        // A cold start: the playlist fetch wins the race with the library load.
        let appState = AppState()
        let fake = makeFake(items: [Self.graceItem()])
        let reader = FakeSongReader(readable: [Self.gracePath: "Amazing Grace"])
        let controller = makeController(appState: appState, reader: reader)
        controller.start()
        defer { controller.stop() }

        await controller.refresh(using: fake.client())
        let adHoc = try #require(controller.playlist?.songs.first)
        #expect(adHoc.libraryID == nil)
        appState.selectedSongID = adHoc.id

        // The library finishes loading and yields the very same file.
        let hymns = Library(url: URL(fileURLWithPath: Self.libraryPath, isDirectory: true))
        await appState.loadLibraries([hymns]) { _ in
            StubPlaylistLibraryProvider([Self.parsedGrace()])
        }

        let collapsed = await waitUntil { controller.playlist?.songs.first !== adHoc }
        #expect(collapsed)
        let shown = try #require(controller.playlist?.songs.first)
        #expect(shown.libraryID == hymns.id)
        // One Song per file: the sidebar shows the same object in both places.
        #expect(appState.songs.count == 1)
        #expect(appState.songs.first === shown)
        #expect(appState.selectedSong === shown)
    }

    @Test("a library twin that lands while the file is being read wins over a fresh copy")
    func libraryTwinArrivingDuringReadIsUsed() async throws {
        let appState = AppState()
        let fake = makeFake(items: [Self.graceItem()])
        let read = BlockingRead()
        let parsed = Self.parsedGrace()
        let controller = PlaylistController(
            appState: appState,
            connection: makeConnection(),
            readSong: { _ in
                read.enter()
                return parsed
            }
        )

        let refresh = Task { await controller.refresh(using: fake.client()) }
        #expect(await waitUntil { read.hasStarted })
        // The library load streams in the twin of the very file being read. It
        // is still mid-load, so there is no generation bump to relink on: the
        // read itself has to notice.
        appState.songs.append(
            Song(
                id: "Amazing Grace",
                title: "Amazing Grace",
                filePath: URL(fileURLWithPath: Self.gracePath),
                libraryID: Self.libraryPath,
                libraryName: "Hymns"
            )
        )
        read.resume()
        await refresh.value

        let shown = try #require(controller.playlist?.songs.first)
        #expect(shown.libraryID == Self.libraryPath)
        // And no ad-hoc copy of the same file was registered next to it.
        #expect(appState.songs.count == 1)
    }

    @Test("a library load that finishes mid-refresh still collapses what the refresh publishes")
    func libraryLoadFinishingDuringRefreshIsRelinked() async throws {
        let appState = AppState()
        let fake = makeFake(items: [Self.graceItem(index: 0), Self.wayMakerItem(index: 1)])
        let reader = FakeSongReader(
            readable: [Self.gracePath: "Amazing Grace", Self.outsidePath: "Way Maker"]
        )
        let controller = makeController(appState: appState, reader: reader)
        let hymns = Library(url: URL(fileURLWithPath: Self.libraryPath, isDirectory: true))
        let parsed = Self.parsedGrace()

        // The library load finishes while the refresh is still resolving item 2:
        // its relink runs before this refresh has published anything, so the
        // refresh would otherwise publish the ad-hoc copy it resolved first.
        fake.beforeResponse = { path in
            guard path == "/v1/presentation/P2" else { return }
            await appState.loadLibraries([hymns]) { _ in StubPlaylistLibraryProvider([parsed]) }
        }

        await controller.refresh(using: fake.client())

        let shown = try #require(controller.playlist?.songs.first)
        #expect(shown.libraryID == hymns.id)
        #expect(appState.songs.contains { $0 === shown })
        // One Song per file: the ad-hoc copy is gone from the sidebar too.
        #expect(appState.songs.count { $0.title == "Amazing Grace" } == 1)
    }

    // MARK: - Cancellation

    @Test("a cancelled refresh keeps the last known playlist instead of a partial one")
    func cancelledRefreshKeepsFullPlaylist() async {
        let appState = makeAppState()
        let fake = makeFake(items: [Self.graceItem(index: 0), Self.wayMakerItem(index: 1)])
        let reader = FakeSongReader(readable: [Self.outsidePath: "Way Maker"])
        let controller = makeController(appState: appState, reader: reader)

        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.songs.count == 2)

        // ProPresenter disappears halfway through the next refresh: the second
        // item is still being fetched when the run task is cancelled.
        let gate = Gate()
        fake.beforeResponse = { [weak fake] path in
            guard path == "/v1/presentation/P2" else { return }
            await gate.wait()
            fake?.presentations["P2"] = nil
        }
        let task = Task { await controller.refresh(using: fake.client()) }
        _ = await waitUntil { fake.requestedPaths.contains("/v1/presentation/P2") }
        task.cancel()
        gate.open()
        await task.value

        #expect(controller.playlist?.songs.count == 2)
        #expect(controller.status == .offline)
    }

    // MARK: - Active vs focused

    @Test("a cue in another playlist does not re-resolve the focused playlist")
    func activeUpdateForAnotherPlaylistIsIgnored() async {
        let fake = makeFake()
        // PL1 is focused; the operator triggers a cue from the announcements
        // playlist, which is all `playlist/active` reports.
        fake.focusUpdates = [
            FakeProPresenter.statusUpdateJSON(
                url: "/v1/playlist/active",
                data: FakeProPresenter.activeJSON(uuid: "PL2", name: "Announcements")
            ),
        ]
        let controller = makeController(appState: AppState())
        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.id == "PL1")

        let outcome = await controller.waitForChange(using: fake.client())

        #expect(outcome == .ended)
        #expect(controller.playlist?.id == "PL1")
    }

    @Test("without a focused playlist only a moving active playlist counts")
    func repeatedActiveUpdateIsIgnored() async {
        let fake = makeFake()
        fake.focused = "{}"
        let announcements = FakeProPresenter.activeJSON(uuid: "PL2", name: "Announcements")
        fake.active = announcements
        fake.playlists["PL2"] = FakeProPresenter.playlistJSON(
            uuid: "PL2", name: "Announcements", items: []
        )
        // Chunked endpoints resend their current state on every connect.
        fake.focusUpdates = [
            FakeProPresenter.statusUpdateJSON(url: "/v1/playlist/active", data: announcements),
            FakeProPresenter.statusUpdateJSON(url: "/v1/playlist/active", data: announcements),
        ]
        let controller = makeController(appState: AppState())
        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.id == "PL2")

        #expect(await controller.waitForChange(using: fake.client()) == .ended)
    }

    @Test("without a focused playlist a different active playlist is a change")
    func movedActivePlaylistIsAChange() async {
        let fake = makeFake()
        fake.focused = "{}"
        fake.active = FakeProPresenter.activeJSON(uuid: "PL2", name: "Announcements")
        fake.playlists["PL2"] = FakeProPresenter.playlistJSON(
            uuid: "PL2", name: "Announcements", items: []
        )
        fake.focusUpdates = [
            FakeProPresenter.statusUpdateJSON(
                url: "/v1/playlist/active",
                data: FakeProPresenter.activeJSON(uuid: "PL3", name: "Evening Service")
            ),
        ]
        let controller = makeController(appState: AppState())
        await controller.refresh(using: fake.client())

        #expect(await controller.waitForChange(using: fake.client()) == .changed)
    }

    // MARK: - Helpers

    /// The library's own parse of the file the playlist already loaded ad hoc:
    /// same presentation uuid, same path.
    private static func parsedGrace() -> ParsedSong {
        ParsedSong(
            id: "Amazing Grace",
            title: "Amazing Grace",
            author: "",
            slideGroups: [
                ParsedSlideGroup(
                    id: "grace-g1",
                    name: "Verse 1",
                    slides: [
                        ParsedSlide(
                            id: "grace-s1",
                            lines: [ParsedLine(id: "grace-l1", original: "Amazing Grace", translation: "")]
                        ),
                    ]
                ),
            ],
            filePath: URL(fileURLWithPath: Self.gracePath)
        )
    }

    /// Polls the main actor until `condition` holds, or gives up after ~2s.
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

// MARK: - Test doubles

/// A library provider that emits exactly the parsed songs it is given — the
/// library load that only finishes *after* the playlist has resolved.
@MainActor
private final class StubPlaylistLibraryProvider: SongProvider {
    private let parsed: [ParsedSong]

    init(_ parsed: [ParsedSong]) {
        self.parsed = parsed
    }

    func loadSongs() -> AsyncStream<SongLoadEvent> {
        AsyncStream { continuation in
            continuation.yield(.started(total: parsed.count))
            for (index, song) in parsed.enumerated() {
                continuation.yield(.parsed(song, loaded: index + 1))
            }
            continuation.finish()
        }
    }
}

/// A one-shot gate: the fake parks a response on it so the test can cancel the
/// refresh that is waiting, then let the response through.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard !opened else {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}

/// A `.pro` read that parks until the test lets it through — the window in which
/// a library load can produce the twin of the file being read.
private final class BlockingRead: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private let release = DispatchSemaphore(value: 0)

    var hasStarted: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }

    /// Called off the main actor, from the detached read.
    func enter() {
        lock.lock()
        started = true
        lock.unlock()
        _ = release.wait(timeout: .now() + 5)
    }

    func resume() {
        release.signal()
    }
}
