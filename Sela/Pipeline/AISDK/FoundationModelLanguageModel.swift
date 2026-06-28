import AISDKProvider
import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Apple Intelligence (on-device **FoundationModels**) wrapped as a custom
/// `LanguageModelV3`, routed through the unified `AISDKTranslationStep` like every
/// other engine.
///
/// Unlike the REST backends (DeepL, Google Translate, MyMemory) this *is* a real
/// LLM, so it produces the structured `[{number,text}]` result itself via
/// FoundationModels guided generation (`@Generable`) and returns it as the JSON
/// the unified step parses. Producing the structured object on-device (rather than
/// letting the SDK do a second `generateObject` round-trip) keeps the whole
/// translation on-device and avoids any HTTP.
///
/// It consumes the *full* standardized prompt — system instructions plus the
/// numbered user lines — so refine mode (which carries the existing `NL:` lines)
/// works the same as translate mode. The on-device call is injected so prompt
/// extraction, JSON serialization, and number mapping can be tested without Apple
/// Intelligence (which CI never has, and not every device supports). The default
/// closure performs the real guided-generation call and is gated to macOS 26+.
struct FoundationModelLanguageModel: LanguageModelV3 {
    let provider = "apple-foundation-models"
    let modelId = "apple-on-device"

    /// Runs the on-device model over the standardized prompt and returns one
    /// `TranslationLine` per input line, keyed by the **same** number. Injectable
    /// for tests; defaults to the real FoundationModels guided-generation call.
    private let generate: @Sendable (LanguageModelV3Prompt) async throws -> [TranslationLine]

    init(
        generate: @escaping @Sendable (LanguageModelV3Prompt) async throws -> [TranslationLine]
            = Self.onDeviceGenerate
    ) {
        self.generate = generate
    }

    /// Timeout for the on-device call; a stalled generation is cancelled so the UI
    /// doesn't hang on "Translating…" forever.
    static let timeout: Duration = .seconds(60)

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let translations = try await generate(options.prompt)
        return CustomTranslationOutput.generateResult(for: TranslationResult(translations: translations))
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        CustomTranslationOutput.streamResult(for: try await doGenerate(options: options))
    }

    // MARK: - On-device generation

    /// Default on-device translator. Feeds the standardized prompt's system and
    /// user text to FoundationModels and asks for a structured `[{number,text}]`
    /// result via guided generation. FoundationModels generates one line per input
    /// in prompt order; the source-line numbers are re-keyed from the extracted
    /// prompt so mapping survives any reordering the model introduces.
    static let onDeviceGenerate: @Sendable (LanguageModelV3Prompt) async throws -> [TranslationLine] = { prompt in
        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                return try await generateOnDevice(prompt)
            }
        #endif
        throw AISDKModelError.unsupportedEngine(.foundationModel)
    }

    /// Keys on-device results by the model-echoed number (dropping any number not
    /// in the source set), so a reordered or omitted line can't be misassigned by
    /// position. Exposed for testing.
    static func keyByNumber(_ pairs: [(number: Int, text: String)], valid: Set<Int>) -> [TranslationLine] {
        pairs.compactMap { pair in
            guard valid.contains(pair.number) else { return nil }
            return TranslationLine(number: pair.number, text: pair.text)
        }
    }

    /// Concatenates the prompt's system messages into a single instruction string.
    /// Exposed for testing.
    static func systemText(from prompt: LanguageModelV3Prompt) -> String {
        prompt.compactMap { message -> String? in
            guard case let .system(content, _) = message else { return nil }
            return content
        }.joined(separator: "\n\n")
    }

    /// Concatenates the text parts of the prompt's user messages. Exposed for
    /// testing.
    static func userText(from prompt: LanguageModelV3Prompt) -> String {
        prompt.compactMap { message -> String? in
            guard case let .user(content, _) = message else { return nil }
            return content.compactMap { part -> String? in
                guard case let .text(textPart) = part else { return nil }
                return textPart.text
            }.joined()
        }.joined(separator: "\n")
    }

    #if canImport(FoundationModels)
        @available(macOS 26, *)
        private static func generateOnDevice(_ prompt: LanguageModelV3Prompt) async throws -> [TranslationLine] {
            let sourceLines = CustomTranslationPrompt.sourceLines(from: prompt)
            guard !sourceLines.isEmpty else { return [] }
            let validNumbers = Set(sourceLines.map(\.number))
            let system = systemText(from: prompt)
            let user = userText(from: prompt)

            // Cancel the on-device call if it stalls past the timeout.
            let respondTask = Task<[GuidedTranslationLine], Error> {
                let session = LanguageModelSession { system }
                let response = try await session.respond(to: user, generating: GuidedTranslationResult.self)
                return response.content.translations
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                respondTask.cancel()
            }
            let lines: [GuidedTranslationLine]
            do {
                lines = try await respondTask.value
                timeoutTask.cancel()
            } catch {
                timeoutTask.cancel()
                throw error
            }

            // Map by the number the model echoed (guided by the @Generable schema),
            // not by position, so a reorder or omission can't misassign a line.
            return keyByNumber(lines.map { ($0.number, $0.text) }, valid: validNumbers)
        }

        /// Guided-generation schema mirroring `TranslationResult` so the on-device
        /// model returns structured per-line translations instead of free text.
        @available(macOS 26, *)
        @Generable
        struct GuidedTranslationResult {
            @Guide(description: "One Dutch worship translation per input line, in the same order as the input.")
            var translations: [GuidedTranslationLine]
        }

        @available(macOS 26, *)
        @Generable
        struct GuidedTranslationLine {
            @Guide(description: "The 1-based line number from the input, repeated exactly.")
            var number: Int
            @Guide(description: "The Dutch worship translation for this line.")
            var text: String
        }
    #endif
}
