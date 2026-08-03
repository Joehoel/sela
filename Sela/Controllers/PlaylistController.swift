import Foundation
import Observation

/// Which playlist the sidebar shows.
enum PlaylistSelection: Equatable {
    /// Whatever ProPresenter has focused (falling back to the active playlist).
    case followProPresenter
    /// One playlist the user picked; its contents are still followed live.
    case manual(id: String, name: String)

    var followsProPresenter: Bool {
        self == .followProPresenter
    }

    /// The playlist id to fetch, or `nil` when ProPresenter decides.
    var playlistID: String? {
        guard case let .manual(id, _) = self else { return nil }
        return id
    }
}

/// What the playlist section should tell the user.
enum PlaylistStatus: Equatable {
    /// The controller has not run yet.
    case idle
    /// Fetching and resolving.
    case loading
    /// `PlaylistController.playlist` is current.
    case ready
    /// Connected, but ProPresenter has neither a focused nor an active playlist.
    case unavailable
    /// No connection; any playlist still shown is the last known one.
    case offline
    /// The playlist could not be fetched.
    case failed(String)

    var summary: String {
        switch self {
        case .idle: "Not connected"
        case .loading: "Loading playlist…"
        case .ready: "Up to date"
        case .unavailable: "No playlist focused in ProPresenter"
        case .offline: "ProPresenter is not reachable"
        case let .failed(reason): reason
        }
    }
}

/// Keeps the focused ProPresenter playlist in sync and resolves every item onto
/// an editable `Song`.
///
/// The controller follows `ProPresenterConnection`: as soon as a verified client
/// appears it fetches the playlist, resolves the items, and then parks on the
/// streaming endpoints until ProPresenter reports a change. Everything that
/// touches the network goes through the injected `ProPresenterAPIClient`, and
/// reading a `.pro` file from disk is injectable too — the same
/// transport-injection idiom as `ProPresenterAPIClient` and `DeepLLanguageModel`
/// — so the whole state machine runs offline in tests.
@Observable @MainActor
final class PlaylistController {
    /// The resolved playlist, kept as the last known one while offline.
    private(set) var playlist: ServicePlaylist?
    private(set) var status: PlaylistStatus = .idle
    /// Follow mode, or the playlist the user pinned.
    private(set) var selection: PlaylistSelection = .followProPresenter
    /// The playlist tree behind the section-header menu; empty while offline.
    private(set) var availablePlaylists: [ProPresenterPlaylistNode] = []

    /// Not `private`: the item resolution lives in `PlaylistController+Resolution.swift`.
    let appState: AppState
    /// Not `private` either: the streaming half lives in
    /// `PlaylistController+Streaming.swift`.
    let connection: ProPresenterConnection
    /// Reads a `.pro` file from disk. Throws for a missing or unparsable file.
    let readSong: @Sendable (URL) throws -> ParsedSong
    /// Suspends for a duration; injectable so the reconnect damping is instant
    /// in tests.
    let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var libraryTask: Task<Void, Never>?
    /// Ad-hoc songs by standardized file path, so a re-resolve reuses the same
    /// `Song` instance (and with it the user's in-flight edits).
    @ObservationIgnored var adHocSongs: [String: Song] = [:]
    /// Bumped by every `refresh`, so a refresh that was overtaken or cancelled
    /// cannot publish its half-resolved list or its stale status.
    @ObservationIgnored private var refreshGeneration = 0
    /// Whether the last fetch found a playlist focused in ProPresenter. While
    /// one is focused, `playlist/active` says nothing about what Sela shows.
    @ObservationIgnored var hasFocusedPlaylist = false
    /// The playlist the last `playlist/active` value pointed at, so repeats of
    /// the same value are not mistaken for a change.
    @ObservationIgnored var lastActivePlaylistID: String?
    /// Playlists whose `/updates` endpoint answered 404 — deleted in
    /// ProPresenter, most likely. Re-opening that stream only spins.
    @ObservationIgnored var unwatchedPlaylistIDs: Set<String> = []
    /// How long the next stream that dies on open has to wait before the
    /// reconnect. Doubles per failed round and resets as soon as a stream is
    /// useful again, so a permanently broken endpoint costs ever less.
    @ObservationIgnored var subscribeInterval = PlaylistController.minimumSubscribeInterval

    init(
        appState: AppState,
        connection: ProPresenterConnection,
        readSong: @escaping @Sendable (URL) throws -> ParsedSong = { url in
            try ProPresenterReader.parseToDTO(data: Data(contentsOf: url), url: url)
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.appState = appState
        self.connection = connection
        self.readSong = readSong
        self.sleep = sleep
    }

    /// The streams that tell us the operator focused a different playlist.
    static let focusStreams = ["playlist/focused", "playlist/active"]

    /// How long a subscribe attempt has to last before its failure counts as a
    /// genuine disconnect. A stream that dies the moment it opens — a deleted
    /// playlist, an older build without the endpoint — would otherwise spin
    /// through reconnect → refresh → subscribe as fast as ProPresenter answers.
    static let minimumSubscribeInterval = Duration.seconds(5)
    /// The ceiling the damping escalates to. On a build where the stream *always*
    /// fails on open, a fixed 5s would keep a full refresh (one fetch per item)
    /// plus a log line running for the whole session; doubling up to a minute
    /// makes that churn negligible without ever giving up on reconnecting.
    static let maximumSubscribeInterval = Duration.seconds(60)

    // MARK: - Lifecycle

    /// Starts following the connection. Idempotent.
    func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.run()
        }
        libraryTask = Task { [weak self] in
            await self?.followLibraryLoads()
        }
    }

    /// Stops following. The last known playlist stays on screen.
    func stop() {
        runTask?.cancel()
        runTask = nil
        libraryTask?.cancel()
        libraryTask = nil
    }

    /// Re-fetches from scratch — after a selection change, or on demand.
    func reload() {
        let wasRunning = runTask != nil
        stop()
        if wasRunning { start() }
    }

    // MARK: - Selection

    /// Pins one playlist; its contents keep updating, its identity does not.
    func select(id: String, name: String) {
        let selection = PlaylistSelection.manual(id: id, name: name)
        guard selection != self.selection else { return }
        self.selection = selection
        reload()
    }

    /// Back to whatever ProPresenter has focused.
    func followProPresenter() {
        guard !selection.followsProPresenter else { return }
        selection = .followProPresenter
        reload()
    }

    /// Fetches `GET /v1/playlists` for the header menu. A failure leaves the last
    /// known tree in place: the menu still offers "Follow ProPresenter", which is
    /// the only entry that works without ProPresenter anyway.
    func loadAvailablePlaylists() async {
        guard let client = connection.client else {
            availablePlaylists = []
            return
        }
        do {
            availablePlaylists = try await client.playlists()
        } catch is CancellationError {
            return
        } catch {
            log(error, context: "playlist tree")
        }
    }

    // MARK: - Connection loop

    /// Keeps the playlist fresh for as long as a client exists, and parks on the
    /// connection whenever one appears or disappears.
    private func run() async {
        while !Task.isCancelled {
            await withTaskGroup(of: Void.self) { group in
                if let client = connection.client {
                    group.addTask {
                        await self.refresh(using: client)
                        await self.subscribe(using: client)
                    }
                } else {
                    // The playlist stays on screen as the last known service.
                    status = playlist == nil ? .idle : .offline
                }
                await awaitClientChange()
                group.cancelAll()
            }
            // `onChange` fires just before the new value is stored.
            await Task.yield()
        }
    }

    /// Suspends until `ProPresenterConnection.client` is replaced, or until this
    /// task is cancelled.
    private func awaitClientChange() async {
        await awaitChange { _ = self.connection.client }
    }

    // MARK: - Library loads

    /// Re-links the playlist onto the library every time a library load
    /// finishes.
    ///
    /// At a cold start the playlist is usually resolved before the libraries
    /// have streamed in, so its items land as ad-hoc copies. Without this the
    /// duplicates would survive the whole session, and the PRD's promise — a
    /// path that matches a loaded song *is* that song — would only hold when
    /// the libraries happened to win the race.
    private func followLibraryLoads() async {
        while !Task.isCancelled {
            await awaitChange { _ = self.appState.libraryLoadGeneration }
            guard !Task.isCancelled else { return }
            // `onChange` fires just before the new value is stored.
            await Task.yield()
            await relinkLoadedSongs()
        }
    }

    /// Replaces the ad-hoc songs in the shown playlist by their library twin,
    /// now that the libraries are loaded.
    func relinkLoadedSongs() async {
        guard let current = playlist else { return }
        var items = current.items
        var changed = false
        for (index, item) in items.enumerated() {
            guard case let .song(adHoc) = item, adHoc.libraryID == nil,
                  let path = adHoc.filePath else { continue }
            guard let replacement = await song(atPath: path.path), replacement !== adHoc else { continue }
            items[index] = .song(replacement)
            changed = true
        }
        guard changed, let current = playlist else { return }
        playlist = ServicePlaylist(id: current.id, name: current.name, items: items)
    }

    /// Suspends until one of the observable values `read` touches changes, or
    /// until this task is cancelled.
    private func awaitChange(_ read: @escaping () -> Void) async {
        let box = ContinuationBox()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.store(continuation)
                withObservationTracking(read) {
                    box.resume()
                }
            }
        } onCancel: {
            box.resume()
        }
    }

    // MARK: - Fetching

    /// Fetches the selected playlist and resolves every item.
    ///
    /// A refresh only ever publishes a *complete* list: cancelled halfway — the
    /// connection dropped, or a newer refresh took over — it leaves the last
    /// known playlist alone instead of replacing it with the items it got to.
    func refresh(using client: ProPresenterAPIClient) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        // Which libraries were loaded when this refresh started resolving. A
        // load that finishes while it runs relinks a playlist this refresh has
        // not published yet, so the relink has to be repeated afterwards.
        let libraryGeneration = appState.libraryLoadGeneration
        status = .loading

        let target = await targetPlaylist(using: client)
        guard generation == refreshGeneration else { return }
        guard case let .playlist(id) = target else {
            reportMissingTarget(target)
            return
        }

        do {
            let fetched = try await client.playlist(id: id.uuid.isEmpty ? id.name : id.uuid)
            let items = try await resolve(fetched.items, using: client)
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            let name = fetched.id.name.isEmpty ? id.name : fetched.id.name
            let uuid = fetched.id.uuid.isEmpty ? id.uuid : fetched.id.uuid
            playlist = ServicePlaylist(id: uuid, name: name, items: items)
            unwatchedPlaylistIDs.remove(uuid)
            status = .ready
            if appState.libraryLoadGeneration != libraryGeneration {
                // A library finished loading while this refresh was resolving,
                // so its relink ran before there was anything to relink.
                await relinkLoadedSongs()
            }
        } catch is CancellationError {
            guard generation == refreshGeneration else { return }
            status = .offline
        } catch {
            guard generation == refreshGeneration else { return }
            log(error, context: "playlist fetch")
            status = .failed(error.localizedDescription)
        }
    }

    /// What a refresh shows when there is no playlist to fetch.
    ///
    /// Only an answer that really says "nothing focused, nothing active" clears
    /// the playlist. A fetch that failed says nothing at all: dropping the
    /// service off the sidebar over a timeout would be wrong, so the last known
    /// one stays with the reason next to it.
    private func reportMissingTarget(_ target: TargetPlaylist) {
        if Task.isCancelled {
            status = .offline
            return
        }
        switch target {
        case .playlist:
            return
        case .nothingFocused:
            playlist = nil
            status = .unavailable
        case let .failed(error):
            log(error, context: "focused playlist")
            status = .failed(error.localizedDescription)
        }
    }

    /// What the focus fetches worked out.
    private enum TargetPlaylist {
        /// The playlist to fetch.
        case playlist(ProPresenterObjectID)
        /// ProPresenter answered both fetches, and has neither a focused nor an
        /// active playlist.
        case nothingFocused
        /// A fetch failed, so nothing is known — and nothing may be discarded.
        case failed(Error)
    }

    /// The playlist to fetch: the pinned one, else focused, else active.
    ///
    /// An unreachable or hung ProPresenter fails these fetches in a way that is
    /// indistinguishable from an empty answer at the value level, so the failure
    /// is reported instead of folded into "nothing is focused".
    private func targetPlaylist(using client: ProPresenterAPIClient) async -> TargetPlaylist {
        if case let .manual(id, name) = selection {
            hasFocusedPlaylist = false
            return .playlist(ProPresenterObjectID(uuid: id, name: name))
        }

        var failure: Error?
        do {
            if let playlist = try await client.focusedPlaylist().playlist,
               !playlist.uuid.isEmpty || !playlist.name.isEmpty {
                hasFocusedPlaylist = true
                return .playlist(playlist)
            }
        } catch {
            // Still worth asking for the active playlist: a build that does not
            // serve `playlist/focused` at all would otherwise never resolve.
            failure = error
        }

        hasFocusedPlaylist = false
        do {
            if let playlist = try await client.activePlaylist().presentation?.playlist,
               !playlist.uuid.isEmpty || !playlist.name.isEmpty {
                lastActivePlaylistID = playlist.uuid.isEmpty ? nil : playlist.uuid
                return .playlist(playlist)
            }
        } catch {
            failure = failure ?? error
        }

        if let failure { return .failed(failure) }
        return .nothingFocused
    }

}

/// One-shot continuation guard: an observation callback and a cancellation can
/// race, and only the first of them may resume.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false

    /// Hands the continuation over, resuming it right away when the wait was
    /// already cancelled.
    func store(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            continuation.resume()
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume() {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
