import Foundation

@MainActor
class ProPresenterSongProvider: SongProvider {
    private let libraryURL: URL

    init(libraryURL: URL) {
        self.libraryURL = libraryURL
    }

    func loadSongs() async -> [Song] {
        let urls = Self.enumerateProFiles(in: libraryURL)
        guard !urls.isEmpty else { return [] }

        // Heavy work — file read + protobuf decode + RTF strip + DTO build —
        // runs on the cooperative thread pool via a bounded TaskGroup. We
        // seed `concurrency` workers, then `group.next()` drains one result
        // and enqueues the next file. This keeps memory flat (no unbounded
        // fan-out) and avoids TaskGroup's known quirks with thousands of
        // queued tasks.
        let concurrency = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let parsed = await Self.parseConcurrently(urls: urls, concurrency: concurrency)

        // Convert Sendable DTOs → @Observable model graph on the main actor.
        let songs = parsed.map { Song(parsed: $0) }

        return songs
            .filter { $0.slideGroups.contains { !$0.slides.isEmpty } }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func save(_ song: Song) async throws {
        guard let filePath = song.filePath else { return }

        // Re-read fresh from disk so unknown proto fields are preserved and
        // any external edits to the file are merged with our translation
        // changes rather than clobbered by a stale in-memory cache.
        let data = try Data(contentsOf: filePath)
        var presentation = try RVData_Presentation(serializedBytes: data)
        try ProPresenterWriter.save(song, into: &presentation, at: filePath)
    }

    // MARK: - File discovery

    private static func enumerateProFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "pro" {
            urls.append(url)
        }
        return urls
    }

    // MARK: - Bounded concurrent parse

    private nonisolated static func parseConcurrently(
        urls: [URL],
        concurrency: Int
    ) async -> [ParsedSong] {
        await withTaskGroup(of: ParsedSong?.self, returning: [ParsedSong].self) { group in
            var iter = urls.makeIterator()
            var results: [ParsedSong] = []
            results.reserveCapacity(urls.count)

            // Seed the group with up to `concurrency` tasks.
            for _ in 0 ..< concurrency {
                guard let url = iter.next() else { break }
                group.addTask { Self.parseOne(url: url) }
            }

            // Drain one, enqueue one, until both the iterator and the group
            // are empty. This is the `group.next()` bounded-concurrency pattern.
            while let result = await group.next() {
                if Task.isCancelled { break }
                if let result { results.append(result) }
                if let url = iter.next() {
                    group.addTask { Self.parseOne(url: url) }
                }
            }

            return results
        }
    }

    private nonisolated static func parseOne(url: URL) -> ParsedSong? {
        guard !Task.isCancelled,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? ProPresenterReader.parseToDTO(data: data, url: url)
    }
}
