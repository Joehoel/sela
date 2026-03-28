import AppKit
import Foundation
@testable import Sela
import SwiftProtobuf
import Testing

struct RTFHelperTests {
    private func fixtureURL(_ name: String) -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures/\(name)")
    }

    /// Load RTF data from the first text element of the first cue in a fixture
    private func loadRTFData(from fixture: String = "Way Maker") throws -> Data {
        let url = fixtureURL("\(fixture).pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        for cue in presentation.cues {
            for action in cue.actions {
                let slide = action.slide.presentation.baseSlide
                for element in slide.elements {
                    let rtf = element.element.text.rtfData
                    if !rtf.isEmpty {
                        return Data(rtf)
                    }
                }
            }
        }
        throw TestError(message: "No RTF data found in \(fixture).pro")
    }

    struct TestError: Error {
        let message: String
    }

    @Test("extractText returns plain text from RTF data")
    func extractText() throws {
        let rtfData = try loadRTFData()

        let text = RTFHelper.extractText(from: rtfData)

        #expect(!text.isEmpty, "Expected non-empty text from RTF data")
    }

    @Test("replaceText preserves font and color attributes")
    func replaceTextPreservesFormatting() throws {
        let rtfData = try loadRTFData()
        let originalAttributed = try #require(NSAttributedString(rtf: rtfData, documentAttributes: nil))

        let replaced = RTFHelper.replaceText(in: rtfData, with: "Vertaalde tekst")
        let replacedAttributed = try #require(NSAttributedString(rtf: replaced, documentAttributes: nil))

        // Text should be replaced
        #expect(replacedAttributed.string == "Vertaalde tekst")

        // Font and color from the original's first character should be preserved
        let originalAttrs = originalAttributed.attributes(at: 0, effectiveRange: nil)
        let replacedAttrs = replacedAttributed.attributes(at: 0, effectiveRange: nil)

        let originalFont = try #require(originalAttrs[.font] as? NSFont)
        let replacedFont = try #require(replacedAttrs[.font] as? NSFont)
        #expect(originalFont.fontName == replacedFont.fontName)
        #expect(originalFont.pointSize == replacedFont.pointSize)

        if let originalColor = originalAttrs[.foregroundColor] as? NSColor,
           let replacedColor = replacedAttrs[.foregroundColor] as? NSColor
        {
            #expect(originalColor == replacedColor)
        }
    }

    @Test("round-trip: extract then replace with same text yields identical text")
    func roundTrip() throws {
        let rtfData = try loadRTFData()

        let originalText = RTFHelper.extractText(from: rtfData)
        let replaced = RTFHelper.replaceText(in: rtfData, with: originalText)
        let roundTrippedText = RTFHelper.extractText(from: replaced)

        #expect(originalText == roundTrippedText)
    }
}
