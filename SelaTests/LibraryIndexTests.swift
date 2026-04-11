import Foundation
@testable import Sela
import Testing

/// RED tests for Phase 3: on-disk library index caching.
@MainActor
struct LibraryIndexTests {
    // MARK: - Fixture helpers

    private func fixturesDir() -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures")
    }

    private func makeTempLibrary(copying fixtures: [String]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sela-libidx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let src = fixturesDir()
        for name in fixtures {
            try FileManager.default.copyItem(
                at: src.appendingPathComponent(name),
                to: tmp.appendingPathComponent(name)
            )
        }
        return tmp
    }

    private func tempIndexURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sela-idx-\(UUID().uuidString).json")
    }

    // MARK: - Index persistence

    @Test("load from missing file returns empty index")
    func loadMissingReturnsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let index = LibraryIndex.load(from: missing)
        #expect(index.entries.isEmpty)
        #expect(index.version == LibraryIndex.currentVersion)
    }

    @Test("save then load round-trips an entry")
    func saveLoadRoundTrip() throws {
        let url = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var index = LibraryIndex()
        let parsed = ParsedSong(
            id: "abc",
            title: "Amazing",
            author: "John",
            slideGroups: [
                ParsedSlideGroup(
                    id: "g1",
                    name: "Verse 1",
                    slides: [ParsedSlide(id: "s1", lines: [
                        ParsedLine(id: "l1", original: "Hello", translation: "Hallo"),
                    ])]
                ),
            ],
            filePath: URL(fileURLWithPath: "/tmp/a.pro")
        )
        index.entries["/tmp/a.pro"] = LibraryIndex.Entry(mtime: 123.0, size: 4096, parsed: parsed)
        try index.save(to: url)

        let reloaded = LibraryIndex.load(from: url)
        #expect(reloaded.entries.count == 1)
        let entry = try #require(reloaded.entries["/tmp/a.pro"])
        #expect(entry.mtime == 123.0)
        #expect(entry.size == 4096)
        #expect(entry.parsed.title == "Amazing")
        #expect(entry.parsed.slideGroups.first?.slides.first?.lines.first?.original == "Hello")
    }

    @Test("version mismatch returns empty index (cache bust)")
    func versionMismatchBustsCache() throws {
        let url = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Hand-write an index with a wrong version
        let stale = #"{"version": 999999, "entries": {}}"#
        try Data(stale.utf8).write(to: url)

        let loaded = LibraryIndex.load(from: url)
        #expect(loaded.entries.isEmpty)
        #expect(loaded.version == LibraryIndex.currentVersion)
    }

    @Test("corrupt JSON returns empty index")
    func corruptJsonReturnsEmpty() throws {
        let url = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("this is not json".utf8).write(to: url)
        let loaded = LibraryIndex.load(from: url)
        #expect(loaded.entries.isEmpty)
    }

    // MARK: - Provider caching behavior

    @Test("first load reports all misses and zero hits")
    func firstLoadAllMisses() async throws {
        let dir = try makeTempLibrary(copying: ["Welkom.pro", "Amazing Grace.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let idx = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: idx) }

        let provider = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await provider.loadSongsArray()

        #expect(provider.lastLoadStats.cacheHits == 0)
        #expect(provider.lastLoadStats.cacheMisses == 2)
    }

    @Test("first load writes the index file to disk")
    func firstLoadWritesIndex() async throws {
        let dir = try makeTempLibrary(copying: ["Welkom.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let idx = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: idx) }

        let provider = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await provider.loadSongsArray()

        #expect(FileManager.default.fileExists(atPath: idx.path))
        let loaded = LibraryIndex.load(from: idx)
        #expect(loaded.entries.count == 1)
    }

    @Test("second load with unchanged files is a full cache hit")
    func secondLoadCacheHits() async throws {
        let dir = try makeTempLibrary(copying: ["Welkom.pro", "Amazing Grace.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let idx = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: idx) }

        // First load: populate cache
        let first = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await first.loadSongsArray()

        // Second load: should hit cache
        let second = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        let songs = await second.loadSongsArray()

        #expect(second.lastLoadStats.cacheHits == 2)
        #expect(second.lastLoadStats.cacheMisses == 0)
        #expect(songs.count >= 1, "Should return at least the translatable songs via cache")
    }

    @Test("changed mtime causes re-parse")
    func changedMtimeReparses() async throws {
        let dir = try makeTempLibrary(copying: ["Welkom.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let idx = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: idx) }

        // First load: populate cache
        let first = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await first.loadSongsArray()

        // Bump mtime on the fixture (touch into the future)
        let fileURL = dir.appendingPathComponent("Welkom.pro")
        let future = Date(timeIntervalSinceNow: 3600)
        try FileManager.default.setAttributes(
            [.modificationDate: future],
            ofItemAtPath: fileURL.path
        )

        // Second load: should re-parse
        let second = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await second.loadSongsArray()

        #expect(second.lastLoadStats.cacheHits == 0)
        #expect(second.lastLoadStats.cacheMisses == 1)
    }

    @Test("deleted file is pruned from index on next load")
    func deletedFilePruned() async throws {
        let dir = try makeTempLibrary(copying: ["Welkom.pro", "Amazing Grace.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let idx = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: idx) }

        // First load: 2 entries in index
        let first = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await first.loadSongsArray()
        let afterFirst = LibraryIndex.load(from: idx)
        #expect(afterFirst.entries.count == 2)

        // Delete one file
        try FileManager.default.removeItem(at: dir.appendingPathComponent("Welkom.pro"))

        // Second load: index should contain only the remaining file
        let second = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        _ = await second.loadSongsArray()
        let afterSecond = LibraryIndex.load(from: idx)
        #expect(afterSecond.entries.count == 1)
        #expect(afterSecond.entries.keys.contains { $0.hasSuffix("Amazing Grace.pro") })
    }

    @Test("cached load still emits correct stream events in order")
    func cachedStreamEvents() async throws {
        let dir = try makeTempLibrary(copying: ["Welkom.pro", "Amazing Grace.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let idx = tempIndexURL()
        defer { try? FileManager.default.removeItem(at: idx) }

        // Warm the cache
        _ = await ProPresenterSongProvider(libraryURL: dir, indexURL: idx).loadSongsArray()

        let provider = ProPresenterSongProvider(libraryURL: dir, indexURL: idx)
        var events: [SongLoadEvent] = []
        for await event in provider.loadSongs() {
            events.append(event)
        }

        guard case let .started(total) = events.first else {
            Issue.record("Expected first event to be .started")
            return
        }
        #expect(total == 2)

        let parsedCount = events.count(where: { if case .parsed = $0 { true } else { false } })
        #expect(parsedCount == 2)
    }
}
