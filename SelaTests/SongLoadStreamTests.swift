import Foundation
@testable import Sela
import Testing

/// RED tests for Phase 2 streaming loader. These fail to compile until the
/// `SongProvider` protocol and `ProPresenterSongProvider` are updated to
/// return `AsyncStream<SongLoadEvent>`.
@MainActor
struct SongLoadStreamTests {
    private func fixturesDir() -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures")
    }

    private func tempDir(copying fixtures: [String]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
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

    // MARK: - Provider-level stream tests

    @Test("stream emits .started with discovered total before any .parsed event")
    func streamStartedFirst() async throws {
        let dir = try tempDir(copying: ["Welkom.pro", "Amazing Grace.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        var events: [SongLoadEvent] = []
        for await event in provider.loadSongs() {
            events.append(event)
        }

        guard case let .started(total) = events.first else {
            Issue.record("Expected first event to be .started, got \(String(describing: events.first))")
            return
        }
        #expect(total == 2)
    }

    @Test("stream emits .parsed events with incrementing loaded counter")
    func streamParsedIncrementsLoaded() async throws {
        let dir = try tempDir(copying: ["Welkom.pro", "Amazing Grace.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        var loadedCounts: [Int] = []
        for await event in provider.loadSongs() {
            if case let .parsed(_, loaded) = event {
                loadedCounts.append(loaded)
            }
        }
        #expect(loadedCounts == [1, 2])
    }

    @Test("stream yields exactly one .parsed per .pro file")
    func streamParsedCount() async throws {
        let dir = try tempDir(copying: ["Welkom.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        var parsedCount = 0
        for await event in provider.loadSongs() {
            if case .parsed = event { parsedCount += 1 }
        }
        #expect(parsedCount == 1)
    }

    @Test("empty directory stream emits .started(0) and then finishes")
    func streamEmptyDir() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        var events: [SongLoadEvent] = []
        for await event in provider.loadSongs() {
            events.append(event)
        }
        #expect(events.count == 1)
        if case let .started(total) = events.first {
            #expect(total == 0)
        } else {
            Issue.record("Expected .started event, got \(String(describing: events.first))")
        }
    }

    // MARK: - AppState streaming tests

    @Test("AppState surfaces totalCount after .started event")
    func appStateTotalCount() async {
        let state = AppState()
        let stub = StreamingStubProvider()
        let loading = Task { await state.loadSongs(from: stub) }

        await stub.yieldWhenReady(.started(total: 7))
        stub.finish()
        await loading.value

        #expect(state.totalCount == 7)
        #expect(state.isLoading == false)
    }

    @Test("AppState appends songs incrementally as .parsed events arrive")
    func appStateIncrementalAppend() async {
        let state = AppState()
        let stub = StreamingStubProvider()

        let song1 = ParsedSong(
            id: "a", title: "Amazing",
            author: "", slideGroups: [groupWithOneSlide(id: "a1")],
            filePath: URL(fileURLWithPath: "/tmp/a.pro")
        )
        let song2 = ParsedSong(
            id: "b", title: "Build",
            author: "", slideGroups: [groupWithOneSlide(id: "b1")],
            filePath: URL(fileURLWithPath: "/tmp/b.pro")
        )

        let loading = Task { await state.loadSongs(from: stub) }

        await stub.yieldWhenReady(.started(total: 2))
        await stub.yieldWhenReady(.parsed(song1, loaded: 1))
        await stub.yieldWhenReady(.parsed(song2, loaded: 2))
        stub.finish()
        await loading.value

        #expect(state.loadedCount == 2)
        #expect(state.songs.count == 2)
        #expect(state.songs.map(\.title).sorted() == ["Amazing", "Build"])
    }

    @Test("AppState filters out songs with no non-empty slide groups")
    func appStateFiltersEmptyGroups() async {
        let state = AppState()
        let stub = StreamingStubProvider()

        let empty = ParsedSong(
            id: "empty", title: "Empty",
            author: "", slideGroups: [ParsedSlideGroup(id: "g", name: "g", slides: [])],
            filePath: URL(fileURLWithPath: "/tmp/e.pro")
        )
        let real = ParsedSong(
            id: "real", title: "Real",
            author: "", slideGroups: [groupWithOneSlide(id: "r1")],
            filePath: URL(fileURLWithPath: "/tmp/r.pro")
        )

        let loading = Task { await state.loadSongs(from: stub) }
        await stub.yieldWhenReady(.started(total: 2))
        await stub.yieldWhenReady(.parsed(empty, loaded: 1))
        await stub.yieldWhenReady(.parsed(real, loaded: 2))
        stub.finish()
        await loading.value

        #expect(state.songs.count == 1)
        #expect(state.songs.first?.title == "Real")
    }

    @Test("AppState sorts songs alphabetically after stream completes")
    func appStateSortsOnCompletion() async {
        let state = AppState()
        let stub = StreamingStubProvider()

        let songs = [
            ("c", "Charlie"),
            ("a", "alpha"),
            ("b", "Bravo"),
        ].map { id, title in
            ParsedSong(
                id: id, title: title, author: "",
                slideGroups: [groupWithOneSlide(id: "\(id)1")],
                filePath: URL(fileURLWithPath: "/tmp/\(id).pro")
            )
        }

        let loading = Task { await state.loadSongs(from: stub) }
        await stub.yieldWhenReady(.started(total: 3))
        for (idx, parsed) in songs.enumerated() {
            await stub.yieldWhenReady(.parsed(parsed, loaded: idx + 1))
        }
        stub.finish()
        await loading.value

        #expect(state.songs.map(\.title) == ["alpha", "Bravo", "Charlie"])
    }

    @Test("AppState cancellation via parent task stops consuming stream")
    func appStateCancellation() async {
        let state = AppState()
        let stub = StreamingStubProvider()

        let loading = Task { await state.loadSongs(from: stub) }
        await stub.yieldWhenReady(.started(total: 100))
        loading.cancel()
        stub.finish()
        await loading.value

        #expect(state.isLoading == false)
    }

    // MARK: - Test helpers

    private func groupWithOneSlide(id: String) -> ParsedSlideGroup {
        ParsedSlideGroup(
            id: id, name: "Group",
            slides: [
                ParsedSlide(
                    id: "slide-\(id)",
                    lines: [ParsedLine(id: "line-\(id)", original: "Hello", translation: "")]
                ),
            ]
        )
    }
}

// MARK: - Streaming stub provider

/// Provider that lets tests drive the load stream manually by yielding events
/// on demand. `yieldWhenReady` blocks until `loadSongs()` has been called and
/// the continuation is wired up, so tests don't race with the consumer task.
@MainActor
final class StreamingStubProvider: SongProvider {
    private var continuation: AsyncStream<SongLoadEvent>.Continuation?
    private var pendingWaits: [CheckedContinuation<Void, Never>] = []

    func loadSongs() -> AsyncStream<SongLoadEvent> {
        let (stream, cont) = AsyncStream<SongLoadEvent>.makeStream()
        self.continuation = cont
        for waiter in pendingWaits {
            waiter.resume()
        }
        pendingWaits.removeAll()
        return stream
    }

    func save(_: Song) async throws {}

    /// Wait until `loadSongs()` has been called, then yield the event.
    func yieldWhenReady(_ event: SongLoadEvent) async {
        if continuation == nil {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                pendingWaits.append(cont)
            }
        }
        continuation?.yield(event)
        // Give the consumer a chance to process the event before we return.
        await Task.yield()
        await Task.yield()
    }

    func finish() {
        continuation?.finish()
    }
}
