import Foundation

@MainActor
class ProPresenterSongProvider: SongProvider {
    private let libraryURL: URL
    private let indexURL: URL
    private(set) var lastLoadStats = LoadStats()

    /// Cache hit/miss counters from the most recent `loadSongs()` call.
    struct LoadStats: Equatable {
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
    }

    init(libraryURL: URL, indexURL: URL? = nil) {
        self.libraryURL = libraryURL
        self.indexURL = indexURL ?? LibraryIndex.defaultURL(for: libraryURL)
    }

    func loadSongs() -> AsyncStream<SongLoadEvent> {
        let libraryURL = self.libraryURL
        let indexURL = self.indexURL
        return AsyncStream<SongLoadEvent> { continuation in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                let urls = Self.enumerateProFiles(in: libraryURL)
                continuation.yield(.started(total: urls.count))

                guard !urls.isEmpty else {
                    // Prune any stale entries from the index even if the
                    // library is now empty.
                    try? LibraryIndex().save(to: indexURL)
                    await Self.publish(stats: LoadStats(), to: self)
                    continuation.finish()
                    return
                }

                let cached = LibraryIndex.load(from: indexURL)
                let concurrency = max(2, ProcessInfo.processInfo.activeProcessorCount)
                let result = await Self.streamWithCache(
                    urls: urls,
                    concurrency: concurrency,
                    cached: cached,
                    continuation: continuation
                )

                if !Task.isCancelled {
                    try? result.index.save(to: indexURL)
                }
                await Self.publish(stats: result.stats, to: self)
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

    // MARK: - Cache-aware streaming parse

    private struct ParseResult {
        let url: URL
        let song: ParsedSong?
        let mtime: TimeInterval
        let size: Int64
        let fromCache: Bool
    }

    private struct CacheLoadResult {
        var index: LibraryIndex
        var stats: LoadStats
    }

    private nonisolated static func streamWithCache(
        urls: [URL],
        concurrency: Int,
        cached: LibraryIndex,
        continuation: AsyncStream<SongLoadEvent>.Continuation
    ) async -> CacheLoadResult {
        await withTaskGroup(
            of: ParseResult.self,
            returning: CacheLoadResult.self
        ) { group in
            var iter = urls.makeIterator()
            var updated = LibraryIndex()
            var stats = LoadStats()
            var loaded = 0

            for _ in 0 ..< concurrency {
                guard let url = iter.next() else { break }
                let entry = cached.entries[url.path]
                group.addTask { Self.loadOrParse(url: url, cached: entry) }
            }

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let song = result.song {
                    loaded += 1
                    updated.entries[result.url.path] = LibraryIndex.Entry(
                        mtime: result.mtime,
                        size: result.size,
                        parsed: song
                    )
                    if result.fromCache {
                        stats.cacheHits += 1
                    } else {
                        stats.cacheMisses += 1
                    }
                    continuation.yield(.parsed(song, loaded: loaded))
                }
                if let url = iter.next() {
                    let entry = cached.entries[url.path]
                    group.addTask { Self.loadOrParse(url: url, cached: entry) }
                }
            }

            return CacheLoadResult(index: updated, stats: stats)
        }
    }

    private nonisolated static func loadOrParse(
        url: URL,
        cached: LibraryIndex.Entry?
    ) -> ParseResult {
        let empty = ParseResult(url: url, song: nil, mtime: 0, size: 0, fromCache: false)
        guard !Task.isCancelled else { return empty }

        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let modDate = attrs[.modificationDate] as? Date,
            let sizeNumber = attrs[.size] as? NSNumber
        else { return empty }

        let mtime = modDate.timeIntervalSince1970
        let size = sizeNumber.int64Value

        if let cached, cached.mtime == mtime, cached.size == size {
            return ParseResult(
                url: url, song: cached.parsed,
                mtime: mtime, size: size, fromCache: true
            )
        }

        guard let data = try? Data(contentsOf: url),
              let parsed = try? ProPresenterReader.parseToDTO(data: data, url: url)
        else { return empty }

        return ParseResult(
            url: url, song: parsed,
            mtime: mtime, size: size, fromCache: false
        )
    }

    // MARK: - Stats publishing

    private nonisolated static func publish(
        stats: LoadStats,
        to provider: ProPresenterSongProvider?
    ) async {
        await MainActor.run {
            provider?.lastLoadStats = stats
        }
    }
}
