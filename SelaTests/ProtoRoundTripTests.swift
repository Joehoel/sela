import Foundation
@testable import Sela
import SwiftProtobuf
import Testing

struct ProtoRoundTripTests {
    private func fixtureURL(_ name: String) -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures/\(name)")
    }

    @Test("decode Way Maker presentation from .pro file")
    func decodeWayMaker() throws {
        let url = fixtureURL("Way Maker.pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        #expect(presentation.name == "Way Maker")
        #expect(!presentation.cues.isEmpty)
        #expect(!presentation.cueGroups.isEmpty)
    }

    @Test("decode Amazing Grace with CCLI metadata")
    func decodeAmazingGrace() throws {
        let url = fixtureURL("Amazing Grace.pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        #expect(!presentation.name.isEmpty)
        #expect(!presentation.cues.isEmpty)
    }

    @Test("cues contain slides with text elements")
    func cuesHaveTextElements() throws {
        let url = fixtureURL("Way Maker.pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        // Find a cue with a slide action containing text elements
        var foundText = false
        for cue in presentation.cues {
            for action in cue.actions {
                let slide = action.slide.presentation.baseSlide
                for element in slide.elements {
                    if element.element.hasText, !element.element.text.rtfData.isEmpty {
                        foundText = true
                    }
                }
            }
        }
        #expect(foundText, "Expected at least one text element with RTF data")
    }

    @Test("RTF data can be decoded to plain text via NSAttributedString")
    func rtfToPlainText() throws {
        let url = fixtureURL("Way Maker.pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        // Extract first non-empty RTF
        var plainText: String?
        outer: for cue in presentation.cues {
            for action in cue.actions {
                let slide = action.slide.presentation.baseSlide
                for element in slide.elements {
                    let rtf = element.element.text.rtfData
                    guard !rtf.isEmpty else { continue }
                    let attributed = NSAttributedString(rtf: Data(rtf), documentAttributes: nil)
                    plainText = attributed?.string
                    if plainText != nil { break outer }
                }
            }
        }

        #expect(plainText != nil, "Expected to extract plain text from RTF")
        #expect(try !(#require(plainText?.isEmpty)))
    }

    @Test("cue groups reference valid cue UUIDs")
    func cueGroupsReferenceValidCues() throws {
        let url = fixtureURL("Way Maker.pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)

        let cueIDs = Set(presentation.cues.map(\.uuid.string))

        for group in presentation.cueGroups {
            for cueRef in group.cueIdentifiers {
                #expect(cueIDs.contains(cueRef.string), "Group '\(group.group.name)' references unknown cue \(cueRef.string)")
            }
        }
    }
}
