import AppKit
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

    /// Indices of the text elements in a cue's action, matching the writer's
    /// own selection logic (`hasText` && non-empty `rtfData`).
    private func textElementIndices(_ cue: RVData_Cue, action: Int) -> [Int] {
        let elements = cue.actions[action].slide.presentation.baseSlide.elements
        return elements.indices.filter {
            elements[$0].element.hasText && !elements[$0].element.text.rtfData.isEmpty
        }
    }

    @Test("write translation then re-read returns the new text")
    func writeAndReread() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)

        let slide = try #require(song.slideGroups.flatMap(\.slides).first)
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

        for slide in song.slideGroups.flatMap(\.slides) {
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

    @Test("save creates .bak backup of original file")
    func saveCreatesBackup() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)

        let output = tempURL()
        let backupURL = output.appendingPathExtension("bak")

        // Write initial version
        let originalData = try presentation.serializedData()
        try originalData.write(to: output)

        // Modify and save — should create backup
        song.slideGroups.flatMap(\.slides).first?.lines.first?.translation = "Backup test"
        try ProPresenterWriter.save(song, into: &presentation, at: output)

        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        // Backup should contain the original data
        let backupData = try Data(contentsOf: backupURL)
        #expect(backupData == originalData)

        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.removeItem(at: backupURL)
    }

    @Test("translation inherits original formatting when the translation box is empty")
    func emptyTranslationBoxInheritsOriginalFormatting() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)

        let slide = try #require(song.slideGroups.flatMap(\.slides).first)
        let line = try #require(slide.lines.first)

        // Locate the cue backing this slide and an action with two text boxes.
        let cueIndex = try #require(presentation.cues.firstIndex { $0.uuid.string == slide.id })
        let actionIndex = try #require(
            presentation.cues[cueIndex].actions.indices
                .first { textElementIndices(presentation.cues[cueIndex], action: $0).count >= 2 }
        )
        let idx = textElementIndices(presentation.cues[cueIndex], action: actionIndex)
        let originalIdx = idx[0]
        let translationIdx = idx[1]

        // Give the ORIGINAL box a distinctive, non-default style so the bug is
        // unambiguous: HelveticaNeue-Bold 71pt, white, centered.
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let boldFont = try #require(NSFont(name: "HelveticaNeue-Bold", size: 71))
        let rich = NSAttributedString(
            string: "Original line",
            attributes: [.font: boldFont, .foregroundColor: NSColor.white, .paragraphStyle: para]
        )
        let richRTF = try #require(rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))

        // Simulate a freshly-made, EMPTY translation box: valid RTF, zero chars.
        let emptyRTF = try #require(
            NSAttributedString(string: "").rtf(from: NSRange(location: 0, length: 0), documentAttributes: [:])
        )

        presentation.cues[cueIndex].actions[actionIndex]
            .slide.presentation.baseSlide.elements[originalIdx].element.text.rtfData = richRTF
        presentation.cues[cueIndex].actions[actionIndex]
            .slide.presentation.baseSlide.elements[translationIdx].element.text.rtfData = emptyRTF

        line.translation = "Vertaalde tekst"

        let output = tempURL()
        try ProPresenterWriter.save(song, into: &presentation, at: output)

        // Inspect the raw RTF the writer produced for the translation box.
        let saved = try RVData_Presentation(serializedBytes: try Data(contentsOf: output))
        let savedRTF = Data(
            saved.cues[cueIndex].actions[actionIndex]
                .slide.presentation.baseSlide.elements[translationIdx].element.text.rtfData
        )
        let savedAttr = try #require(NSAttributedString(rtf: savedRTF, documentAttributes: nil))

        #expect(savedAttr.string == "Vertaalde tekst")
        let attrs = savedAttr.attributes(at: 0, effectiveRange: nil)
        let savedFont = try #require(attrs[.font] as? NSFont)
        #expect(savedFont.fontName == "HelveticaNeue-Bold", "translation font should match the original box")
        #expect(savedFont.pointSize == 71, "translation size should match the original box")
        let savedPara = try #require(attrs[.paragraphStyle] as? NSParagraphStyle)
        #expect(savedPara.alignment == .center, "translation alignment should match the original box")
        if let color = attrs[.foregroundColor] as? NSColor {
            #expect(color.whiteComponent == 1.0, "translation color should match the original box")
        }

        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.removeItem(at: output.appendingPathExtension("bak"))
    }

    @Test("full round-trip: read, modify, save, re-read, verify")
    func fullRoundTrip() throws {
        let url = fixtureURL("Welkom.pro")
        var (song, presentation) = try ProPresenterReader.read(from: url)
        let groupCount = song.slideGroups.count

        let allSlides = song.slideGroups.flatMap(\.slides)
        for (i, slide) in allSlides.enumerated() {
            slide.lines.first?.translation = "Vertaling \(i)"
        }

        let output = tempURL()
        try ProPresenterWriter.save(song, into: &presentation, at: output)

        let (reread, _) = try ProPresenterReader.read(from: output)
        #expect(reread.slideGroups.count == groupCount)

        let rereadSlides = reread.slideGroups.flatMap(\.slides)
        for (i, slide) in rereadSlides.enumerated() {
            #expect(slide.lines.first?.translation == "Vertaling \(i)")
        }

        try? FileManager.default.removeItem(at: output)
    }
}
