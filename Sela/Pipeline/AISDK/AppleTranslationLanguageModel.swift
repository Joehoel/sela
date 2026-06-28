import AISDKProvider
import Foundation
@preconcurrency import Translation

enum AppleTranslationError: LocalizedError, Equatable {
    case unavailable
    case languagePairNotInstalled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Translation needs macOS 26 or later."
        case .languagePairNotInstalled:
            "The English → Dutch language pair isn’t installed. Open the Translate app and download Dutch, then try again."
        case .invalidResponse:
            "Apple Translation returned an unexpected response."
        }
    }
}

/// Apple's on-device **Translation** framework wrapped as a *headless* custom
/// `LanguageModelV3`, routed through the unified `AISDKTranslationStep` like every
/// other engine. It is not an LLM and needs no API key, so the shared
/// `CustomTranslationLanguageModel` base turns the numbered prompt into source
/// lines, calls this `translate(_:)`, and serializes the result into the
/// structured JSON the step expects.
///
/// Headless-only (macOS 26+): the session is built directly with
/// `TranslationSession(installedSource:target:)` — no SwiftUI `.translationTask`
/// view bridge. Because a headless session cannot present the download-consent
/// prompt, the engine is only offered when the EN→NL pair is already installed
/// (see `installedLanguagePairAvailable()` and the gating in `TranslationEngine`).
///
/// Each line is sent as a `TranslationSession.Request` tagged with its 1-based
/// line number as `clientIdentifier`; responses are mapped back onto that number,
/// so any reordering by the framework can't misassign a translation. The translate
/// step is injected so request building and response/error mapping can be tested
/// without the framework.
@available(macOS 26, *)
struct AppleTranslationLanguageModel: CustomTranslationLanguageModel {
    let provider = "apple-translation"
    let modelId = "apple-on-device"

    /// One translated line as returned by the framework, narrowed to the fields we
    /// use. Exposed (and `Sendable`) so the injected translate closure can be built
    /// without importing `Translation` in tests.
    struct Translated: Sendable, Equatable {
        let targetText: String
        let clientIdentifier: String?
    }

    /// One request to translate, narrowed to the fields we use. Exposed so the
    /// injected translate closure can read the source text and identifier without
    /// importing `Translation`.
    struct Request: Sendable, Equatable {
        let sourceText: String
        let clientIdentifier: String?
    }

    /// Translates a batch of requests on-device, preserving the `clientIdentifier`
    /// on each response. Injectable for tests; defaults to the real headless
    /// `TranslationSession` call.
    private let translateBatch: @Sendable ([Request]) async throws -> [Translated]

    init(
        translateBatch: @escaping @Sendable ([Request]) async throws -> [Translated]
            = AppleTranslationLanguageModel.onDeviceTranslate
    ) {
        self.translateBatch = translateBatch
    }

    func translate(_ lines: [CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine] {
        guard !lines.isEmpty else { return [] }

        let responses = try await translateBatch(Self.requests(for: lines))

        // Index translations by clientIdentifier so order-independent mapping back
        // onto the source-line numbers is structural, never positional.
        var byIdentifier: [String: String] = [:]
        byIdentifier.reserveCapacity(responses.count)
        for response in responses {
            guard let identifier = response.clientIdentifier else {
                throw AppleTranslationError.invalidResponse
            }
            byIdentifier[identifier] = response.targetText
        }

        return try lines.map { line in
            guard let text = byIdentifier[String(line.number)] else {
                throw AppleTranslationError.invalidResponse
            }
            return TranslationLine(number: line.number, text: text)
        }
    }

    /// Builds one request per source line, tagging each with its line number as
    /// `clientIdentifier` so responses map back by number. Exposed for testing.
    static func requests(for lines: [CustomTranslationPrompt.SourceLine]) -> [Request] {
        lines.map { Request(sourceText: $0.text, clientIdentifier: String($0.number)) }
    }

    // MARK: - On-device translation

    private static let source = Locale.Language(identifier: "en")
    private static let target = Locale.Language(identifier: "nl")

    /// Default on-device translator: builds a headless `TranslationSession` for the
    /// already-installed EN→NL pair and translates the batch, preserving each
    /// request's `clientIdentifier`.
    static let onDeviceTranslate: @Sendable ([Request]) async throws -> [Translated] = { requests in
        let session = TranslationSession(installedSource: source, target: target)
        let frameworkRequests = requests.map {
            TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.clientIdentifier)
        }
        let responses = try await session.translations(from: frameworkRequests)
        return responses.map {
            Translated(targetText: $0.targetText, clientIdentifier: $0.clientIdentifier)
        }
    }

    /// Whether the EN→NL pair is already installed on this host. The headless
    /// session can't present the download prompt, so the engine is only offered
    /// when this is `true`. macOS 26+ only.
    static func installedLanguagePairAvailable() async -> Bool {
        await LanguageAvailability().status(from: source, to: target) == .installed
    }
}
