import Foundation
@testable import Sela
import Testing

/// What `PlaylistController` does when ProPresenter answers badly: an update
/// stream that dies the moment it opens, a pinned playlist that no longer
/// exists, and a ProPresenter that stops answering altogether. The damping that
/// keeps those from turning into a hot loop is the subject here.
///
/// Same setup as `PlaylistControllerTests`: an in-memory ProPresenter behind an
/// injected transport, plus an injected sleep so the waits are instant.
@MainActor
struct PlaylistControllerDampingTests {
    // MARK: - Fixtures

    private static let gracePath = "/tmp/SelaTests/Libraries/Hymns/Amazing Grace.pro"

    /// A ProPresenter focused on "Sunday Service" (PL1), with one presentation.
    private func makeFake(items: [String] = []) -> FakeProPresenter {
        let fake = FakeProPresenter()
        fake.focused = FakeProPresenter.focusJSON(uuid: "PL1", name: "Sunday Service")
        fake.playlists["PL1"] = FakeProPresenter.playlistJSON(
            uuid: "PL1", name: "Sunday Service", items: items
        )
        fake.presentations["P1"] = FakeProPresenter.presentationJSON(uuid: "P1", path: Self.gracePath)
        return fake
    }

    private func makeConnection(client: ProPresenterAPIClient? = nil) -> ProPresenterConnection {
        ProPresenterConnection(
            preferences: UserPreferences(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!),
            makeClient: { _ in client },
            discover: { [] },
            wait: { _ in }
        )
    }

    private func makeController(appState: AppState) -> PlaylistController {
        PlaylistController(
            appState: appState,
            connection: makeConnection(),
            readSong: { _ in throw CocoaError(.fileReadNoSuchFile) }
        )
    }

    /// An app state holding the song the playlist item points at.
    private func makeAppState() -> AppState {
        let appState = AppState()
        appState.songs = [
            Song(
                id: "loaded-grace",
                title: "Amazing Grace",
                filePath: URL(fileURLWithPath: Self.gracePath),
                libraryID: "/tmp/SelaTests/Libraries/Hymns",
                libraryName: "Hymns"
            ),
        ]
        return appState
    }

    private static func graceItem(index: Int = 0) -> String {
        FakeProPresenter.presentationItem(index: index, name: "Amazing Grace", uuid: "P1")
    }

    // MARK: - Tests

    @Test("a pinned playlist ProPresenter no longer has is not watched over and over")
    func deletedPinnedPlaylistStopsBeingWatched() async {
        let fake = makeFake()
        fake.playlists["PL9"] = FakeProPresenter.playlistJSON(
            uuid: "PL9", name: "Christmas Eve", items: []
        )
        let controller = makeController(appState: AppState())
        controller.select(id: "PL9", name: "Christmas Eve")
        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.id == "PL9")

        // The operator deletes the pinned playlist in ProPresenter.
        fake.playlists["PL9"] = nil
        await controller.refresh(using: fake.client())

        // Last known playlist stays on screen, with the reason next to it.
        #expect(controller.playlist?.id == "PL9")
        #expect(
            controller.status
                == .failed(ProPresenterAPIError.requestFailed(statusCode: 404).localizedDescription)
        )

        // The updates endpoint 404s too — and is not opened a second time.
        #expect(await controller.waitForChange(using: fake.client()) == .ended)
        #expect(await controller.waitForChange(using: fake.client()) == .idle)
        #expect(fake.openedStreamPaths.count { $0.hasSuffix("/updates") } == 1)
    }

    @Test("a stream that dies on open delays the reconnect instead of spinning")
    func immediateStreamFailureIsDamped() async {
        let fake = makeFake()
        let sleeps = DurationRecorder()
        let controller = PlaylistController(
            appState: AppState(),
            connection: makeConnection(client: fake.client()),
            readSong: { _ in throw CocoaError(.fileReadNoSuchFile) },
            sleep: { sleeps.record($0) }
        )
        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.id == "PL1")

        // An older ProPresenter build: the aggregator answers 400 right away.
        fake.statusStreamFails = true
        await controller.subscribe(using: fake.client())

        #expect(sleeps.durations.count == 1)
        #expect(sleeps.durations.first ?? .zero > .seconds(1))
    }

    @Test("a stream that keeps dying on open waits longer every round, up to the cap")
    func repeatedStreamFailureEscalatesDamping() async {
        let fake = makeFake()
        let sleeps = DurationRecorder()
        let controller = PlaylistController(
            appState: AppState(),
            connection: makeConnection(client: fake.client()),
            readSong: { _ in throw CocoaError(.fileReadNoSuchFile) },
            sleep: { sleeps.record($0) }
        )
        await controller.refresh(using: fake.client())

        // A build that never serves the aggregator: every round fails on open.
        fake.statusStreamFails = true
        for _ in 0 ..< 6 {
            await controller.subscribe(using: fake.client())
        }

        let durations = sleeps.durations
        #expect(durations.count == 6)
        #expect(durations[0] > .seconds(4) && durations[0] <= PlaylistController.minimumSubscribeInterval)
        #expect(durations[1] > .seconds(9))
        #expect(durations[3] > .seconds(39))
        // Capped, so the wait never grows out of reach of a returning operator.
        #expect(durations[5] > .seconds(59))
        #expect(durations.allSatisfy { $0 <= PlaylistController.maximumSubscribeInterval })
    }

    @Test("a stream that reports a change resets the escalated damping")
    func streamChangeResetsDamping() async {
        let fake = makeFake()
        let sleeps = DurationRecorder()
        let controller = PlaylistController(
            appState: AppState(),
            connection: makeConnection(client: fake.client()),
            readSong: { _ in throw CocoaError(.fileReadNoSuchFile) },
            sleep: { sleeps.record($0) }
        )
        await controller.refresh(using: fake.client())

        fake.statusStreamFails = true
        await controller.subscribe(using: fake.client())
        await controller.subscribe(using: fake.client())

        // ProPresenter answers again: the content stream reports a change, the
        // re-fetch it triggers goes through, and only then does the aggregator
        // start failing once more.
        fake.rearmStreams()
        fake.statusStreamFails = false
        fake.contentChanges = true
        fake.beforeResponse = { [weak fake] path in
            guard path == "/v1/playlist/focused" else { return }
            fake?.statusStreamFails = true
        }
        await controller.subscribe(using: fake.client())

        let durations = sleeps.durations
        #expect(durations.count == 3)
        #expect(durations[1] > durations[0])
        // Back to the minimum instead of doubling on.
        #expect(durations[2] < durations[0] + .seconds(1))
    }

    @Test("a ProPresenter that stops answering keeps the last known playlist")
    func unreachableProPresenterKeepsLastKnownPlaylist() async {
        let fake = makeFake(items: [Self.graceItem()])
        let controller = makeController(appState: makeAppState())
        await controller.refresh(using: fake.client())
        #expect(controller.playlist?.id == "PL1")

        // ProPresenter crashes or hangs right after reporting a change: the
        // focus fetches fail, which says nothing about what is focused.
        fake.isUnreachable = true
        await controller.refresh(using: fake.client())

        #expect(controller.playlist?.id == "PL1")
        #expect(controller.playlist?.songs.count == 1)
        #expect(
            controller.status
                == .failed(
                    ProPresenterAPIError
                        .unreachable(URLError(.cannotConnectToHost).localizedDescription)
                        .localizedDescription
                )
        )
    }
}

/// Records what the controller asked to sleep for, instead of sleeping.
private final class DurationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Duration] = []

    var durations: [Duration] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func record(_ duration: Duration) {
        lock.lock(); defer { lock.unlock() }
        stored.append(duration)
    }
}
