import Foundation

@MainActor
class ProPresenterSongProvider: SongProvider {
    private let libraryURL: URL

    init(libraryURL: URL) {
        self.libraryURL = libraryURL
    }

    func loadSongs() -> AsyncStream<SongLoadEvent> {
        let libraryURL = self.libraryURL
        return AsyncStream<SongLoadEvent> { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let urls = Self.enumerateProFiles(in: libraryURL)
                continuation.yield(.started(total: urls.count))

                guard !urls.isEmpty else {
                    continuation.finish()
                    return
                }

                let concurrency = max(2, ProcessInfo.processInfo.activeProcessorCount)
                await Self.streamParsedSongs(
                    urls: urls,
                    concurrency: concurrency,
                    continuation: continuation
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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

    private nonisolated static func enumerateProFiles(in root: URL) -> [URL] {
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

    // MARK: - Bounded concurrent streaming parse

    private nonisolated static func streamParsedSongs(
        urls: [URL],
        concurrency: Int,
        continuation: AsyncStream<SongLoadEvent>.Continuation
    ) async {
        await withTaskGroup(of: ParsedSong?.self) { group in
            var iter = urls.makeIterator()
            var loaded = 0

            // Seed workers
            for _ in 0 ..< concurrency {
                guard let url = iter.next() else { break }
                group.addTask { Self.parseOne(url: url) }
            }

            // Drain-and-refill: `group.next()` bounded concurrency pattern
            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let result {
                    loaded += 1
                    continuation.yield(.parsed(result, loaded: loaded))
                }
                if let url = iter.next() {
                    group.addTask { Self.parseOne(url: url) }
                }
            }
        }
    }

    private nonisolated static func parseOne(url: URL) -> ParsedSong? {
        guard !Task.isCancelled,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? ProPresenterReader.parseToDTO(data: data, url: url)
    }
}
