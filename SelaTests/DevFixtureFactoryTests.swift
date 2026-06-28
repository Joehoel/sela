import Foundation
@testable import Sela
import SwiftProtobuf
import Testing

struct DevFixtureFactoryTests {
    private func presentation(_ name: String) throws -> (RVData_Presentation, URL) {
        let url = DevLibrary.fixturesSourceURL.appendingPathComponent("\(name).pro")
        let data = try Data(contentsOf: url)
        return (try RVData_Presentation(serializedBytes: data), url)
    }

    private func translatableLineCount(_ presentation: RVData_Presentation, _ url: URL) -> Int {
        let song = Song(parsed: ProPresenterReader.parseToDTO(presentation: presentation, url: url))
        return song.slideGroups.flatMap(\.slides).flatMap(\.lines).count
    }

    @Test("adds translation boxes to a single-box song, making it translatable")
    func makesSingleBoxTranslatable() throws {
        var (presentation, url) = try presentation("Way Maker")
        #expect(translatableLineCount(presentation, url) == 0, "Way Maker starts with no translatable lines")

        let added = DevFixtureFactory.addTranslationBoxes(to: &presentation)
        #expect(added > 0)
        #expect(translatableLineCount(presentation, url) > 0, "should be translatable after adding boxes")
    }

    @Test("preserves existing translations and only grows the translatable set")
    func preservesExistingTranslations() throws {
        var (presentation, url) = try presentation("Welkom")
        let linesBefore = Song(parsed: ProPresenterReader.parseToDTO(presentation: presentation, url: url))
            .slideGroups.flatMap(\.slides).flatMap(\.lines)
        let translatedBefore = linesBefore.filter { !$0.translation.isEmpty }
        #expect(!translatedBefore.isEmpty)

        _ = DevFixtureFactory.addTranslationBoxes(to: &presentation)

        let linesAfter = Song(parsed: ProPresenterReader.parseToDTO(presentation: presentation, url: url))
            .slideGroups.flatMap(\.slides).flatMap(\.lines)

        // Adding boxes never removes lines (existing two-box slides are untouched).
        #expect(linesAfter.count >= linesBefore.count)
        // Already-filled translations are preserved exactly.
        for line in translatedBefore {
            let match = linesAfter.first { $0.id == line.id }
            #expect(match?.translation == line.translation, "translation for \(line.id) should be unchanged")
        }
    }

    @Test("seeding makes most fixtures translatable")
    func seedingExpandsTranslatableLibrary() throws {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        DevLibrary.seed(into: dest, from: DevLibrary.fixturesSourceURL)

        let proFiles = try FileManager.default
            .contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "pro" }

        let translatable = proFiles.filter { url in
            guard let (song, _) = try? ProPresenterReader.read(from: url) else { return false }
            return !song.slideGroups.flatMap(\.slides).flatMap(\.lines).isEmpty
        }

        // Before this change only Welkom + Amazing Grace were usable (2).
        #expect(translatable.count >= 4, "expected the dev library to surface more translatable songs, got \(translatable.count)")
    }
}
