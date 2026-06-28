import AISDKProvider
import Foundation

/// Helpers for building a custom `LanguageModelV3` over a non-LLM backend
/// (DeepL, Google Translate, MyMemory, Apple Translation, …) so it runs through
/// the same unified `AISDKTranslationStep` as the LLM providers.
///
/// The unified step builds a numbered prompt and parses a structured
/// `TranslationResult` out of the model's `.text` output. A non-LLM backend
/// can't produce that JSON itself, so the shared `CustomTranslationLanguageModel`
/// base does it for the backend: it extracts the numbered source lines from the
/// standardized prompt, hands them to the backend, and serializes the returned
/// lines into the exact JSON the step expects.
enum CustomTranslationPrompt {
    /// One numbered source line lifted out of the standardized prompt. The number
    /// is the 1-based line index the unified step assigned; the backend must
    /// return it unchanged so translations map back to the correct line.
    struct SourceLine: Sendable, Equatable {
        let number: Int
        let text: String
    }

    /// Extracts the numbered source lines (`"<n>. EN: <text>"`) from the user
    /// messages of a standardized prompt. Group headers, the lead-in sentence,
    /// blank lines, and the system message are ignored.
    static func sourceLines(from prompt: LanguageModelV3Prompt) -> [SourceLine] {
        var lines: [SourceLine] = []
        var seen = Set<Int>()

        for message in prompt {
            guard case let .user(content, _) = message else { continue }
            for part in content {
                guard case let .text(textPart) = part else { continue }
                for rawLine in textPart.text.components(separatedBy: "\n") {
                    guard let parsed = parse(rawLine), !seen.contains(parsed.number) else { continue }
                    seen.insert(parsed.number)
                    lines.append(parsed)
                }
            }
        }
        return lines
    }

    /// Parses a single `"<n>. EN: <text>"` line. Returns `nil` for any other
    /// shape (headers, prose, blanks).
    private static func parse(_ rawLine: String) -> SourceLine? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        var index = line.startIndex
        var digits = ""
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard let number = Int(digits), index < line.endIndex, line[index] == "." else { return nil }

        let afterDot = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard afterDot.hasPrefix("EN:") else { return nil }

        let text = afterDot.dropFirst("EN:".count).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return SourceLine(number: number, text: text)
    }
}

/// A custom `LanguageModelV3` wrapping a non-LLM translation backend. Conformers
/// implement only `translate(_:)`; this protocol supplies `doGenerate` (extract
/// prompt → translate → serialize `TranslationResult` JSON as a single `.text`
/// part, `finishReason: .stop`, `nil` usage) and a `doStream` that wraps it
/// (required by `LanguageModelV3` even for non-streaming backends).
///
/// This is the keystone pattern reused by every custom backend (DeepL, Google
/// Translate, MyMemory, Apple Translation, …).
protocol CustomTranslationLanguageModel: LanguageModelV3 {
    /// Translates the numbered source lines, returning one `TranslationLine` per
    /// input line with the **same** `number` so the unified step maps results
    /// back onto the correct source line.
    func translate(_ lines: [CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine]
}

extension CustomTranslationLanguageModel {
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let sourceLines = CustomTranslationPrompt.sourceLines(from: options.prompt)
        let translations = try await translate(sourceLines)
        return CustomTranslationOutput.generateResult(for: TranslationResult(translations: translations))
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        CustomTranslationOutput.streamResult(for: try await doGenerate(options: options))
    }
}

/// Shared serialization + streaming envelope for custom (non-LLM) and on-device
/// translation models, so every backend emits the unified step's expected
/// `TranslationResult` JSON and the same one-shot stream. Factored out so a fix
/// to the envelope can't drift between backends.
enum CustomTranslationOutput {
    /// One `.text` part carrying the `TranslationResult` JSON, `finishReason: .stop`,
    /// empty usage — the shape the unified `AISDKTranslationStep` parses.
    static func generateResult(for result: TranslationResult) -> LanguageModelV3GenerateResult {
        let json = (try? encode(result)) ?? "{\"translations\":[]}"
        return LanguageModelV3GenerateResult(
            content: [.text(LanguageModelV3Text(text: json))],
            finishReason: LanguageModelV3FinishReason(unified: .stop),
            usage: LanguageModelV3Usage()
        )
    }

    /// Wraps a generate result as a one-shot stream (text-start → delta → end →
    /// finish) for backends that don't stream natively.
    static func streamResult(for result: LanguageModelV3GenerateResult) -> LanguageModelV3StreamResult {
        let text = result.content.compactMap { part -> String? in
            if case let .text(textPart) = part { return textPart.text }
            return nil
        }.joined()

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            let id = "0"
            continuation.yield(.textStart(id: id, providerMetadata: nil))
            continuation.yield(.textDelta(id: id, delta: text, providerMetadata: nil))
            continuation.yield(.textEnd(id: id, providerMetadata: nil))
            continuation.yield(.finish(
                finishReason: result.finishReason,
                usage: result.usage,
                providerMetadata: nil
            ))
            continuation.finish()
        }
        return LanguageModelV3StreamResult(stream: stream)
    }

    static func encode(_ result: TranslationResult) throws -> String {
        let data = try JSONEncoder().encode(result)
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

extension CharacterSet {
    /// Query-/form-value-safe set: `.urlQueryAllowed` minus the sub-delimiters
    /// that have meaning in a query string or `x-www-form-urlencoded` body, so
    /// `&`, `+`, `=`, `?`, `#` are percent-encoded. Hand-rolled query building
    /// (DeepL form body, Google `q=`) must use this to avoid corrupting lyric
    /// lines that contain those characters.
    static let translationQueryValue: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()
}
