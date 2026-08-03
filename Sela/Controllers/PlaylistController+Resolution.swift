import Foundation
import os

/// Turning ProPresenter's playlist items into editable `Song`s: the half of
/// `PlaylistController` that touches `AppState` and the file system, split off
/// from the connection/streaming state machine next door.
extension PlaylistController {
    /// Turns API items into rows. Anything that is not a header and does not map
    /// onto a readable `.pro` file is dropped, and so is anything the operator
    /// hid in ProPresenter — the playlist mirrors the service as shown there.
    ///
    /// Throws `CancellationError` (and nothing else) so a cancelled refresh
    /// cannot be mistaken for a shorter playlist.
    func resolve(
        _ items: [ProPresenterPlaylistItem],
        using client: ProPresenterAPIClient
    ) async throws -> [ServicePlaylistItem] {
        var resolved: [ServicePlaylistItem] = []
        for item in items {
            try Task.checkCancellation()
            guard !item.isHidden else { continue }
            switch item.type {
            case .header:
                resolved.append(.header(item.id.name))
            case .presentation, .placeholder:
                if let song = try await resolveSong(for: item, using: client) {
                    resolved.append(.song(song))
                }
            case .media, .audio, .livevideo, .unknown:
                continue
            }
        }
        return resolved
    }

    /// Item → presentation → `presentation_path` → `Song`.
    func resolveSong(
        for item: ProPresenterPlaylistItem,
        using client: ProPresenterAPIClient
    ) async throws -> Song? {
        guard let uuid = item.presentationUUID else { return nil }
        let presentation: ProPresenterPresentation
        do {
            presentation = try await client.presentation(uuid: uuid)
        } catch {
            // Skipping the item is right for a missing presentation, but wrong
            // for a cancelled fetch: that has to abort the whole refresh.
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            log(error, context: "presentation \(uuid)")
            return nil
        }
        guard let path = presentation.presentationPath, !path.isEmpty else { return nil }
        return await song(atPath: path)
    }

    /// A loaded library song when the path matches one, otherwise a song read
    /// straight off disk and registered with `AppState`.
    func song(atPath path: String) async -> Song? {
        let url = URL(fileURLWithPath: path)
        let key = Self.pathKey(url)

        if let loaded = librarySong(forKey: key) { return loaded }

        if let existing = adHocSongs[key] {
            return existing
        }

        do {
            // Reading and parsing a `.pro` file is the same protobuf work the
            // library loader does off the main actor, so it goes off it here too.
            let read = readSong
            let parsed = try await Task.detached(priority: .userInitiated) { try read(url) }.value
            // The main actor was free while this one was reading: a library load
            // may have streamed in the twin of this very file, and another
            // refresh may have registered it ad hoc. Both win over a fresh copy.
            if let loaded = librarySong(forKey: key) { return loaded }
            if let existing = adHocSongs[key] { return existing }
            let song = Song(parsed: parsed)
            adHocSongs[key] = song
            appState.registerAdHocSong(song)
            return song
        } catch {
            log(error, context: "ad-hoc song at \(path)")
            return nil
        }
    }

    /// The loaded library song for a standardized path, if there is one.
    ///
    /// Finding it also drops the ad-hoc copy of the same file: the file turned up
    /// in a real library after all, so there has to be a single instance with a
    /// single translation state.
    private func librarySong(forKey key: String) -> Song? {
        guard let loaded = appState.songs.first(where: { song in
            song.libraryID != nil && song.filePath.map(Self.pathKey) == key
        }) else { return nil }
        if let stale = adHocSongs.removeValue(forKey: key) {
            appState.unregisterAdHocSong(stale)
        }
        return loaded
    }

    /// Paths come from ProPresenter and from our own enumeration, so they are
    /// compared after normalizing `//`, `..` and symlinks.
    static func pathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: - Logging

    /// Playlist problems are expected in the wild (a media item, a file that
    /// moved, ProPresenter quitting mid-fetch): the item is skipped rather than
    /// surfaced, but never swallowed silently. Local logging only — these
    /// messages carry file paths.
    static let log = Logger(subsystem: "com.sela.app", category: "PlaylistController")

    func log(_ error: Error, context: String) {
        Self.log.warning("\(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}
