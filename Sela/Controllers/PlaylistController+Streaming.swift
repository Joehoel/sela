import Foundation

/// Following ProPresenter's chunked update endpoints: the half of
/// `PlaylistController` that parks on the streams and decides when a re-fetch is
/// due, split off from the fetching/resolving state machine next door.
extension PlaylistController {
    /// Re-fetches on every change ProPresenter reports, until the streams end.
    func subscribe(using client: ProPresenterAPIClient) async {
        while !Task.isCancelled {
            let started = ContinuousClock.now
            switch await waitForChange(using: client) {
            case .changed:
                // The streams work: whatever damping built up is stale.
                subscribeInterval = Self.minimumSubscribeInterval
                await refresh(using: client)
            case .idle:
                return
            case .ended:
                // The stream died: the connection is stale, so let the
                // connection manager search again — but not before the attempt
                // has lasted a while, or a stream that fails on open turns the
                // whole cycle into a hot loop against ProPresenter.
                guard !Task.isCancelled else { return }
                let lifetime = ContinuousClock.now - started
                if lifetime >= Self.minimumSubscribeInterval {
                    // It lived long enough to count as a real connection that
                    // dropped, so the next failure starts over at the minimum.
                    subscribeInterval = Self.minimumSubscribeInterval
                } else {
                    do { try await sleep(subscribeInterval - lifetime) } catch { return }
                    guard !Task.isCancelled else { return }
                    // Still failing on open: back off further, up to the cap.
                    subscribeInterval = min(subscribeInterval * 2, Self.maximumSubscribeInterval)
                }
                connection.reconnect()
                return
            }
        }
    }

    /// Why `waitForChange` returned.
    enum ChangeOutcome: Equatable {
        /// Something we care about changed; re-fetch.
        case changed
        /// The stream closed or failed.
        case ended
        /// There is nothing to watch (no playlist, and not following).
        case idle
    }

    /// Opens the relevant streams and returns as soon as the first one has news.
    /// Both streams are re-opened after every change; ProPresenter only pushes
    /// on operator actions, so that costs nothing in practice.
    func waitForChange(using client: ProPresenterAPIClient) async -> ChangeOutcome {
        let watchesFocus = selection.followsProPresenter
        let shownID = playlist?.id
        let playlistID = shownID.flatMap { unwatchedPlaylistIDs.contains($0) ? nil : $0 }
        guard watchesFocus || playlistID != nil else { return .idle }

        return await withTaskGroup(of: ChangeOutcome.self) { group in
            if watchesFocus {
                group.addTask { await self.waitForFocusChange(using: client) }
            }
            if let playlistID {
                group.addTask { await self.waitForContentChange(of: playlistID, using: client) }
            }
            let outcome = await group.next() ?? .ended
            group.cancelAll()
            return outcome
        }
    }

    /// Watches the focused/active playlist, ignoring the item-level focus events
    /// that fire whenever the operator clicks a song in the same playlist.
    private func waitForFocusChange(using client: ProPresenterAPIClient) async -> ChangeOutcome {
        do {
            for try await update in client.statusUpdates(streams: Self.focusStreams)
                where isFocusChange(update) {
                return .changed
            }
            return .ended
        } catch is CancellationError {
            return .ended
        } catch {
            log(error, context: "playlist focus stream")
            return .ended
        }
    }

    /// Whether a focus/active update means the playlist Sela shows has changed.
    ///
    /// `playlist/focused` decides. `playlist/active` only names the playlist
    /// that owns the most recently triggered cue: an operator triggering
    /// announcements while another playlist is focused is normal, and taking
    /// that for a focus change would re-resolve the playlist over and over —
    /// the streams push their current state on every connect, so it would never
    /// settle. Active therefore only counts while nothing is focused, and only
    /// when it actually moves to another playlist.
    private func isFocusChange(_ update: ProPresenterStatusUpdate) -> Bool {
        if update.url.hasSuffix("playlist/focused") {
            let id = (try? update.decode(ProPresenterPlaylistFocus.self))?.playlist
            guard let uuid = id?.uuid, !uuid.isEmpty else { return false }
            return uuid != playlist?.id
        }
        if update.url.hasSuffix("playlist/active") {
            let id = (try? update.decode(ProPresenterActivePlaylist.self))?.presentation?.playlist
            guard let uuid = id?.uuid, !uuid.isEmpty else { return false }
            let previous = lastActivePlaylistID
            lastActivePlaylistID = uuid
            guard !hasFocusedPlaylist, uuid != previous else { return false }
            return uuid != playlist?.id
        }
        return false
    }

    /// `GET /v1/playlist/{id}/updates?chunked=true` — each chunk is the bare
    /// string `"change"`, meaning "re-fetch me".
    private func waitForContentChange(
        of playlistID: String,
        using client: ProPresenterAPIClient
    ) async -> ChangeOutcome {
        do {
            for try await _ in client.playlistUpdates(id: playlistID) {
                return .changed
            }
            return .ended
        } catch is CancellationError {
            return .ended
        } catch {
            // A playlist the operator deleted answers 404 forever: stop
            // watching it rather than re-opening the stream after every
            // reconnect. The last known playlist stays on screen.
            if (error as? ProPresenterAPIError) == .requestFailed(statusCode: 404) {
                unwatchedPlaylistIDs.insert(playlistID)
            }
            log(error, context: "playlist content stream")
            return .ended
        }
    }
}
