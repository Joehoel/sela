import AppKit
import Foundation
@testable import Sela
import SwiftProtobuf
import Testing

struct RTFTextStripperTests {
    private func fixtureURL(_ name: String) -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures/\(name)")
    }

    /// Walks every RTF blob found in a fixture and calls `body` with each one.
    private func forEachRTFBlob(in fixture: String, _ body: (Data) -> Void) throws {
        let url = fixtureURL("\(fixture).pro")
        let data = try Data(contentsOf: url)
        let presentation = try RVData_Presentation(serializedBytes: data)
        for cue in presentation.cues {
            for action in cue.actions {
                for element in action.slide.presentation.baseSlide.elements
                    where element.element.hasText && !element.element.text.rtfData.isEmpty
                {
                    body(Data(element.element.text.rtfData))
                }
            }
        }
    }

    // MARK: - Parity against NSAttributedString

    @Test(
        "stripper matches NSAttributedString plain text on all fixtures",
        arguments: [
            "Way Maker",
            "Amazing Grace",
            "Build My Life",
            "10000 Reasons",
            "It Is Well",
            "Welkom",
            "Powerpoint psalternatief 9-2-2024",
        ]
    )
    func parity(fixture: String) throws {
        try forEachRTFBlob(in: fixture) { rtf in
            let stripped = RTFTextStripper.extractText(from: rtf)
            let reference = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string ?? ""
            // Normalize: both implementations differ only on trailing paragraph
            // terminators and leading/trailing whitespace. We care that the
            // substantive text content matches character-for-character.
            let normalizedStripped = normalize(stripped)
            let normalizedReference = normalize(reference)
            #expect(
                normalizedStripped == normalizedReference,
                """
                Mismatch in fixture '\(fixture)':
                  stripper:  \(stripped.debugDescription)
                  reference: \(reference.debugDescription)
                """
            )
        }
    }

    /// Collapse whitespace runs to a single space and trim, so minor formatting
    /// differences (trailing \n from \par, consecutive blank lines) don't
    /// count as mismatches.
    private func normalize(_ str: String) -> String {
        str.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    // MARK: - Unit tests on synthetic RTF

    @Test("plain ASCII text passes through")
    func plainText() {
        let rtf = #"{\rtf1\ansi\ansicpg1252 Hello world}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "Hello world")
    }

    @Test("par becomes newline")
    func parIsNewline() {
        // Per RTF spec, the space following a control word is the delimiter
        // and is consumed, so the text after `\par ` starts right after the
        // newline with no leading space.
        let rtf = #"{\rtf1\ansi Line one\par Line two}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "Line one\nLine two")
    }

    @Test("fonttbl group is skipped")
    func fontTableSkipped() {
        let rtf = #"{\rtf1\ansi{\fonttbl\f0\fnil ArialMT;}\f0 Hello}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "Hello")
    }

    @Test("colortbl group is skipped")
    func colorTableSkipped() {
        let rtf = #"{\rtf1\ansi{\colortbl;\red255\green0\blue0;}\cf1 Red text}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "Red text")
    }

    @Test("ignorable destination is skipped")
    func ignorableDestinationSkipped() {
        let rtf = #"{\rtf1\ansi{\*\generator hidden}Visible}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "Visible")
    }

    @Test("hex escape decodes Windows-1252 accented char")
    func hexEscapeAccented() {
        // \'e9 is é in Windows-1252 and Latin-1
        let rtf = #"{\rtf1\ansi\ansicpg1252 caf\'e9}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "café")
    }

    @Test("hex escape decodes Windows-1252 specific extras")
    func hexEscapeCP1252Extras() {
        // \'80 is € in Windows-1252 (maps to U+20AC)
        let rtf = #"{\rtf1\ansi\ansicpg1252 \'80 100}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "€ 100")
    }

    @Test("unicode escape decodes code point")
    func unicodeEscape() {
        let rtf = #"{\rtf1\ansi\ansicpg1252 \u233?}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "é")
    }

    @Test("escaped backslash and braces are literal")
    func escapedSpecials() {
        let rtf = #"{\rtf1\ansi \\backslash \{brace\}}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "\\backslash {brace}")
    }

    @Test("nested skippable group still emits following text")
    func nestedSkippableThenText() {
        let rtf = #"{\rtf1\ansi{\fonttbl{\f0\fnil Arial;}{\f1\fnil Helvetica;}}\f0 Body}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "Body")
    }

    @Test("smart quote control words")
    func smartQuotes() {
        let rtf = #"{\rtf1\ansi \ldblquote Hi\rdblquote}"#
        let result = RTFTextStripper.extractText(from: Data(rtf.utf8))
        #expect(result == "\u{201C}Hi\u{201D}")
    }

    @Test("empty RTF returns empty string")
    func empty() {
        let result = RTFTextStripper.extractText(from: Data())
        #expect(result.isEmpty)
    }
}
