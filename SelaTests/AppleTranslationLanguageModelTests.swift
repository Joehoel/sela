import AISDKProvider
import Foundation
@testable import Sela
import Testing

/// Apple Translation (the on-device `Translation` framework) implemented as a
/// headless custom `LanguageModelV3` (see `CustomTranslationModel`). It builds the
/// session directly with `TranslationSession(installedSource:target:)` — no
/// SwiftUI view / session bridge — and is only offered when the EN→NL pair is
/// already installed (the headless session cannot present the download prompt).
///
/// These tests cover request building (one `Request` per line with the line
/// number as `clientIdentifier`), the `clientIdentifier`-based mapping back onto
/// the source-line numbers (incl. when responses come back reordered), the
/// empty-input short-circuit, and error mapping — all without the framework (the
/// translate closure is injected).
///
/// `AppleTranslationLanguageModel` is `@available(macOS 26, *)`, but Swift Testing
/// cannot apply `@Test` to functions in an availability-constrained type, so each
/// test guards on macOS 26 and no-ops on older hosts (CI runs the rest).
struct AppleTranslationLanguageModelTests {
    // MARK: - Request building

    @Test("builds one Request per line, tagging each with its line number as clientIdentifier")
    func buildsRequests() {
        guard #available(macOS 26, *) else { return }
        let requests = AppleTranslationLanguageModel.requests(for: [
            .init(number: 1, text: "Hello"),
            .init(number: 7, text: "World"),
        ])
        #expect(requests.map(\.sourceText) == ["Hello", "World"])
        #expect(requests.map(\.clientIdentifier) == ["1", "7"])
    }

    // MARK: - translate() mapping (translate closure injected — no framework)

    @Test("maps responses back onto source-line numbers via clientIdentifier")
    func mapsByClientIdentifier() async throws {
        guard #available(macOS 26, *) else { return }
        let model = AppleTranslationLanguageModel { requests in
            requests.map { request in
                AppleTranslationLanguageModel.Translated(
                    targetText: request.sourceText == "Hello" ? "Hallo" : "Wereld",
                    clientIdentifier: request.clientIdentifier
                )
            }
        }

        let result = try await model.translate([
            .init(number: 1, text: "Hello"),
            .init(number: 2, text: "World"),
        ])

        #expect(result == [
            TranslationLine(number: 1, text: "Hallo"),
            TranslationLine(number: 2, text: "Wereld"),
        ])
    }

    @Test("reordered responses still map onto the correct source line via clientIdentifier")
    func mapsReorderedResponses() async throws {
        guard #available(macOS 26, *) else { return }
        let model = AppleTranslationLanguageModel { requests in
            // Return responses in reverse order to prove mapping is by identifier,
            // not by position.
            requests.reversed().map { request in
                AppleTranslationLanguageModel.Translated(
                    targetText: request.sourceText == "Hello" ? "Hallo" : "Wereld",
                    clientIdentifier: request.clientIdentifier
                )
            }
        }

        let result = try await model.translate([
            .init(number: 1, text: "Hello"),
            .init(number: 2, text: "World"),
        ])

        #expect(result == [
            TranslationLine(number: 1, text: "Hallo"),
            TranslationLine(number: 2, text: "Wereld"),
        ])
    }

    @Test("empty source lines short-circuit without calling the framework")
    func emptyLines() async throws {
        guard #available(macOS 26, *) else { return }
        let called = CallFlag()
        let model = AppleTranslationLanguageModel { requests in
            called.mark()
            return requests.map {
                AppleTranslationLanguageModel.Translated(targetText: "", clientIdentifier: $0.clientIdentifier)
            }
        }
        let result = try await model.translate([])
        #expect(result.isEmpty)
        #expect(called.wasCalled == false)
    }

    @Test("a response missing its clientIdentifier maps to invalidResponse")
    func missingClientIdentifier() async throws {
        guard #available(macOS 26, *) else { return }
        let model = AppleTranslationLanguageModel { requests in
            requests.map { _ in
                AppleTranslationLanguageModel.Translated(targetText: "x", clientIdentifier: nil)
            }
        }
        await #expect(throws: AppleTranslationError.invalidResponse) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("a missing translation for a line maps to invalidResponse")
    func missingLine() async throws {
        guard #available(macOS 26, *) else { return }
        let model = AppleTranslationLanguageModel { _ in
            // Returns nothing for line 2.
            [AppleTranslationLanguageModel.Translated(targetText: "Hallo", clientIdentifier: "1")]
        }
        await #expect(throws: AppleTranslationError.invalidResponse) {
            _ = try await model.translate([
                .init(number: 1, text: "Hello"),
                .init(number: 2, text: "World"),
            ])
        }
    }

    @Test("framework errors propagate out of translate")
    func errorPropagates() async throws {
        guard #available(macOS 26, *) else { return }
        struct Boom: Error {}
        let model = AppleTranslationLanguageModel { _ in throw Boom() }
        await #expect(throws: Boom.self) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    // MARK: - Errors

    @Test("AppleTranslationError has user-facing descriptions")
    func errorDescriptions() {
        #expect(AppleTranslationError.languagePairNotInstalled.errorDescription?.isEmpty == false)
        #expect(AppleTranslationError.invalidResponse.errorDescription?.contains("unexpected") == true)
    }
}

/// A tiny thread-safe flag for asserting whether an injected closure ran.
final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false

    func mark() {
        lock.lock(); defer { lock.unlock() }
        called = true
    }

    var wasCalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return called
    }
}
