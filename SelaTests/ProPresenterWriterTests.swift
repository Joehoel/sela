import Foundation
@testable import Sela
import SwiftProtobuf
import Testing

struct ProPresenterWriterTests {
    private func fixtureURL(_ name: String) -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures/\(name)")
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pro")
    }

    @Test("write translation then re-read returns the new text")
    func writeAndReread() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)

        // Find a translatable slide and set a translation on its first line
        let slide = try #require(
            song.slideGroups.flatMap(\.slides)
                .first(where: { $0.isTranslatable })
        )
        let line = try #require(slide.lines.first)
        line.translation = "Welkom bij ons"

        let output = tempURL()
        try ProPresenterWriter.save(song, into: &presentation, at: output)

        // Re-read and verify
        let (reread, _) = try ProPresenterReader.read(from: output)
        let rereadLine = try #require(
            reread.slideGroups.flatMap(\.slides).flatMap(\.lines)
                .first(where: { $0.id == line.id })
        )
        #expect(rereadLine.translation == "Welkom bij ons")

        try? FileManager.default.removeItem(at: output)
    }

    @Test("write preserves original text and presentation metadata")
    func preservesOriginalAndMetadata() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)

        let originalLines = song.slideGroups.flatMap(\.slides).flatMap(\.lines)
        let originals = originalLines.map { ($0.id, $0.original) }

        // Set a translation on every translatable slide
        for slide in song.slideGroups.flatMap(\.slides) where slide.isTranslatable {
            for line in slide.lines {
                line.translation = "Test vertaling"
            }
        }

        let output = tempURL()
        try ProPresenterWriter.save(song, into: &presentation, at: output)

        let (reread, rereadPresentation) = try ProPresenterReader.read(from: output)

        // Original text must be unchanged
        let rereadLines = reread.slideGroups.flatMap(\.slides).flatMap(\.lines)
        for (id, expectedOriginal) in originals {
            let rereadLine = rereadLines.first(where: { $0.id == id })
            #expect(rereadLine?.original == expectedOriginal, "Original text for \(id) should be preserved")
        }

        // Metadata preserved
        #expect(rereadPresentation.name == presentation.name)
        #expect(rereadPresentation.cueGroups.count == presentation.cueGroups.count)
        #expect(rereadPresentation.cues.count == presentation.cues.count)

        try? FileManager.default.removeItem(at: output)
    }

    @Test("full round-trip: read, modify, save, re-read, verify")
    func fullRoundTrip() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)
        let groupCount = song.slideGroups.count

        let translatableSlides = song.slideGroups.flatMap(\.slides)
            .filter(\.isTranslatable)
        for (i, slide) in translatableSlides.enumerated() {
            slide.lines.first?.translation = "Vertaling \(i)"
        }

        let output = tempURL()
        try ProPresenterWriter.save(song, into: &presentation, at: output)

        let (reread, _) = try ProPresenterReader.read(from: output)
        #expect(reread.slideGroups.count == groupCount)

        let rereadTranslatable = reread.slideGroups.flatMap(\.slides)
            .filter(\.isTranslatable)
        for (i, slide) in rereadTranslatable.enumerated() {
            #expect(slide.lines.first?.translation == "Vertaling \(i)")
        }

        try? FileManager.default.removeItem(at: output)
    }
}
