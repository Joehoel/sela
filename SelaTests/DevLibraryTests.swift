import Foundation
@testable import Sela
import Testing

struct DevLibraryTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("shouldUseFixtures is true when the real library is missing or empty")
    func detectsMissingLibrary() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(DevLibrary.shouldUseFixtures(realLibraryURL: missing))

        let empty = try tempDir()
        #expect(DevLibrary.shouldUseFixtures(realLibraryURL: empty))
    }

    @Test("shouldUseFixtures is false when the real library has .pro files")
    func detectsRealLibrary() throws {
        let dir = try tempDir()
        try Data("x".utf8).write(to: dir.appendingPathComponent("Song.pro"))
        #expect(!DevLibrary.shouldUseFixtures(realLibraryURL: dir))
    }

    @Test("seed copies fixtures into a writable dev library without touching the source")
    func seedsWritableCopy() throws {
        let source = DevLibrary.fixturesSourceURL
        let sourceCountBefore = try FileManager.default
            .contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pro" }.count
        #expect(sourceCountBefore > 0, "fixtures should exist at the resolved source path")

        let dest = try tempDir()
        DevLibrary.seed(into: dest, from: source)

        // The seeded copy now looks like a real library...
        #expect(!DevLibrary.shouldUseFixtures(realLibraryURL: dest))
        let copied = try FileManager.default
            .contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pro" }
        #expect(copied.count == sourceCountBefore)

        // ...and the source fixtures are untouched.
        let sourceCountAfter = try FileManager.default
            .contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pro" }.count
        #expect(sourceCountAfter == sourceCountBefore)
    }

    @Test("seeded fixtures yield at least one translatable song through the real provider")
    func fixturesLoadThroughProvider() throws {
        let dest = try tempDir()
        DevLibrary.seed(into: dest, from: DevLibrary.fixturesSourceURL)

        let proFiles = try FileManager.default
            .contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pro" }

        // A song is "translatable" when at least one slide has a line (the
        // reader only emits lines for slides that own a translation text box).
        let translatable = proFiles.compactMap { url -> String? in
            guard let (song, _) = try? ProPresenterReader.read(from: url),
                  let line = song.slideGroups.flatMap(\.slides).flatMap(\.lines).first,
                  !line.original.isEmpty
            else { return nil }
            return song.title
        }

        #expect(!translatable.isEmpty, "dev library should surface at least one translatable song")
    }
}
