import Foundation
@testable import Sela
import SwiftProtobuf
import Testing

struct ProPresenterReaderTests {
    private func fixtureURL(_ name: String) -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures/\(name)")
    }

    @Test("read Way Maker returns correct title and has named groups")
    func readWayMakerTitleAndGroups() throws {
        let url = fixtureURL("Way Maker.pro")

        let (song, _) = try ProPresenterReader.read(from: url)

        #expect(song.title == "Way Maker")
        #expect(!song.slideGroups.isEmpty)
        let groupNames = song.slideGroups.map(\.name)
        #expect(groupNames.contains(where: { $0.lowercased().contains("verse") }))
        #expect(groupNames.contains(where: { $0.lowercased().contains("chorus") }))
    }

    @Test("slides contain original text extracted from RTF")
    func slidesHaveOriginalText() throws {
        let url = fixtureURL("Way Maker.pro")

        let (song, _) = try ProPresenterReader.read(from: url)

        let allLines = song.slideGroups.flatMap(\.slides).flatMap(\.lines)
        #expect(!allLines.isEmpty)
        for line in allLines {
            #expect(!line.original.isEmpty, "Every slide line should have original text")
        }
    }

    @Test("Welkom has translatable slides (2+ text elements per slide)")
    func translatableSlideDetection() throws {
        let url = fixtureURL("Welkom.pro")

        let (song, _) = try ProPresenterReader.read(from: url)

        let allSlides = song.slideGroups.flatMap(\.slides)
        let translatable = allSlides.filter(\.isTranslatable)
        #expect(!translatable.isEmpty, "Welkom should have translatable slides")
    }

    @Test("Way Maker slides without second text element are not translatable")
    func notTranslatable() throws {
        let url = fixtureURL("Way Maker.pro")

        let (song, _) = try ProPresenterReader.read(from: url)

        let allSlides = song.slideGroups.flatMap(\.slides)
        #expect(allSlides.allSatisfy { !$0.isTranslatable })
    }

    @Test("model IDs come from proto UUIDs")
    func protoUUIDsAsModelIDs() throws {
        let url = fixtureURL("Way Maker.pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        let (song, _) = try ProPresenterReader.read(from: url)

        #expect(song.id == presentation.uuid.string)
        #expect(song.slideGroups.first?.id == presentation.cueGroups.first?.group.uuid.string)
    }
}
