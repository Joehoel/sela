import AISDKProvider
import Foundation
@testable import Sela
import SwiftAISDK
import Testing

/// Exercises the reusable custom-`LanguageModelV3` pattern that wraps a non-LLM
/// backend (DeepL, Google Translate, Apple, etc.). The pattern extracts the
/// numbered source lines from the standardized prompt, calls the backend, and
/// returns a single `.text` content part holding the `TranslationResult` JSON so
/// the unified `generateObject` path parses it exactly like an LLM backend.
struct CustomTranslationModelTests {
    // MARK: - Prompt source extraction

    @Test("extracts numbered source lines from the standardized prompt")
    func extractsNumberedLines() {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "instructions", providerOptions: nil),
            .user(content: [.text(.init(text: "1. EN: Hello\n\n2. EN: World\n"))], providerOptions: nil),
        ]
        let lines = CustomTranslationPrompt.sourceLines(from: prompt)
        #expect(lines.count == 2)
        #expect(lines[0].number == 1)
        #expect(lines[0].text == "Hello")
        #expect(lines[1].number == 2)
        #expect(lines[1].text == "World")
    }

    @Test("ignores group headers, blank lines and the lead-in sentence")
    func ignoresNoise() {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: """
            Translate the following English worship song lines to Dutch.

            [Verse 1]
            1. EN: Amazing grace

            2. EN: How sweet the sound
            """))], providerOptions: nil),
        ]
        let lines = CustomTranslationPrompt.sourceLines(from: prompt)
        #expect(lines.map(\.number) == [1, 2])
        #expect(lines.map(\.text) == ["Amazing grace", "How sweet the sound"])
    }

    @Test("concatenates text across multiple user parts")
    func multipleParts() {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "1. EN: Hello")),
                .text(.init(text: "2. EN: World")),
            ], providerOptions: nil),
        ]
        let lines = CustomTranslationPrompt.sourceLines(from: prompt)
        #expect(lines.map(\.text) == ["Hello", "World"])
    }

    // MARK: - doGenerate shape

    @Test("doGenerate returns one .text part with TranslationResult JSON, stop, nil usage")
    func doGenerateShape() async throws {
        let model = StubCustomModel { lines in
            lines.map { TranslationLine(number: $0.number, text: "[\($0.text)]") }
        }
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "1. EN: Hello\n2. EN: World"))], providerOptions: nil),
        ]
        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.finishReason.unified == .stop)
        #expect(result.usage.inputTokens.total == nil)
        #expect(result.usage.outputTokens.total == nil)
        #expect(result.content.count == 1)

        guard case let .text(textPart) = result.content[0] else {
            Issue.record("expected a single .text content part")
            return
        }
        let data = try #require(textPart.text.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TranslationResult.self, from: data)
        #expect(decoded.translations.map(\.number) == [1, 2])
        #expect(decoded.translations.map(\.text) == ["[Hello]", "[World]"])
    }

    @Test("doStream wraps doGenerate and emits the same text then finishes")
    func doStreamWrapsGenerate() async throws {
        let model = StubCustomModel { lines in
            lines.map { TranslationLine(number: $0.number, text: "x") }
        }
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "1. EN: Hello"))], providerOptions: nil),
        ]
        let streamResult = try await model.doStream(options: .init(prompt: prompt))

        var text = ""
        var finished = false
        for try await part in streamResult.stream {
            switch part {
            case let .textDelta(_, delta, _):
                text += delta
            case .finish:
                finished = true
            default:
                break
            }
        }
        #expect(finished)
        let data = try #require(text.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TranslationResult.self, from: data)
        #expect(decoded.translations == [TranslationLine(number: 1, text: "x")])
    }

    @Test("backend errors propagate out of doGenerate")
    func errorPropagates() async {
        struct Boom: Error {}
        let model = StubCustomModel { _ in throw Boom() }
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "1. EN: Hello"))], providerOptions: nil),
        ]
        await #expect(throws: Boom.self) {
            _ = try await model.doGenerate(options: .init(prompt: prompt))
        }
    }

    // MARK: - End-to-end through the unified step (no network)

    @Test("a custom model runs through AISDKTranslationStep and writes translations back")
    func endToEndThroughUnifiedStep() async throws {
        let model = StubCustomModel { lines in
            lines.map { TranslationLine(number: $0.number, text: $0.text == "Hello" ? "Hallo" : "Wereld") }
        }
        let step = AISDKTranslationStep(model: model, mode: .translate)

        var items = [
            TranslationItem(sourceText: "Hello", lineID: "a"),
            TranslationItem(sourceText: "World", lineID: "b"),
        ]
        try await step.process(&items)
        #expect(items[0].currentText == "Hallo")
        #expect(items[1].currentText == "Wereld")
    }
}

/// A minimal concrete custom model used to exercise the shared base behavior
/// (prompt extraction, JSON serialization, `doStream` wrapper) without a backend.
private struct StubCustomModel: CustomTranslationLanguageModel {
    let provider = "stub"
    let modelId = "stub-model"
    let translateLines: @Sendable ([CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine]

    init(_ translateLines: @escaping @Sendable ([CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine]) {
        self.translateLines = translateLines
    }

    func translate(_ lines: [CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine] {
        try await translateLines(lines)
    }
}
