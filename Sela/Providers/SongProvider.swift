import Foundation

/// Event stream produced by `SongProvider.loadSongs()`.
///
/// Stream shape: exactly one `.started(total:)` first, then one `.parsed(_:, loaded:)`
/// per successfully parsed file, then the stream terminates.
enum SongLoadEvent {
    /// Total number of candidate files discovered in the library.
    case started(total: Int)
    /// A parsed song DTO. `loaded` is the cumulative count of `.parsed` events
    /// emitted so far (1-indexed).
    case parsed(ParsedSong, loaded: Int)
}

@MainActor
protocol SongProvider {
    /// Returns an async stream of load events. Construction is cheap; the
    /// stream begins producing events as soon as it is consumed. Cancelling
    /// the consumer cancels the underlying parse task via the stream's
    /// termination handler.
    func loadSongs() -> AsyncStream<SongLoadEvent>
    func save(_ song: Song) async throws
}

extension SongProvider {
    func save(_: Song) async throws {}
}

extension SongProvider {
    /// Convenience for tests and simple call sites: collect the stream into
    /// a sorted array of fully-constructed `Song` instances, filtering out
    /// songs with no non-empty slide groups (matching the pre-streaming
    /// behavior of the old `loadSongs() -> [Song]` API).
    func loadSongsArray() async -> [Song] {
        var songs: [Song] = []
        for await event in loadSongs() {
            if case let .parsed(parsed, _) = event,
               parsed.slideGroups.contains(where: { !$0.slides.isEmpty })
            {
                songs.append(Song(parsed: parsed))
            }
        }
        return songs.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}
