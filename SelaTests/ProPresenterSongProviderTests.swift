import Foundation
@testable import Sela
import Testing

struct ProPresenterSongProviderTests {
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
            let from = src.appendingPathComponent(name)
            let to = tmp.appendingPathComponent(name)
            try FileManager.default.copyItem(at: from, to: to)
        }
        return tmp
    }

    @Test("load songs only returns presentations with translatable slides")
    @MainActor
    func loadSongs() async throws {
        let dir = try tempDir(copying: ["Way Maker.pro", "Amazing Grace.pro", "Welkom.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        let songs = await provider.loadSongs()

        // Way Maker has no translatable slides (no second text element), so it's excluded
        let titles = Set(songs.map(\.title))
        #expect(!titles.contains("Way Maker"))
        #expect(titles.contains("Welkom"))
        for song in songs {
            #expect(song.slideGroups.contains { !$0.slides.isEmpty })
        }
    }

    @Test("save translation then re-load persists the change")
    @MainActor
    func saveTranslationPersists() async throws {
        let dir = try tempDir(copying: ["Welkom.pro"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        let songs = await provider.loadSongs()
        let song = try #require(songs.first)

        let slide = try #require(song.slideGroups.flatMap(\.slides).first)
        let line = try #require(slide.lines.first)
        line.translation = "Hallo wereld"

        try await provider.save(song)

        // Re-load from disk
        let provider2 = ProPresenterSongProvider(libraryURL: dir)
        let reloaded = await provider2.loadSongs()
        let reloadedSong = try #require(reloaded.first)
        let reloadedLine = try #require(
            reloadedSong.slideGroups.flatMap(\.slides).flatMap(\.lines)
                .first(where: { $0.id == line.id })
        )
        #expect(reloadedLine.translation == "Hallo wereld")
    }

    @Test("load from empty directory returns empty array")
    @MainActor
    func emptyDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let provider = ProPresenterSongProvider(libraryURL: dir)
        let songs = await provider.loadSongs()

        #expect(songs.isEmpty)
    }
}
