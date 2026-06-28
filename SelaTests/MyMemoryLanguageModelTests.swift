import AISDKProvider
import Foundation
@testable import Sela
import Testing

/// MyMemory implemented as a custom `LanguageModelV3` (see `CustomTranslationModel`).
/// It wraps the free MyMemory REST API and stays key-free. These tests cover
/// request building, response parsing, the daily-quota error, HTTP error mapping,
/// and the source-line → `TranslationLine` mapping — all without touching the
/// network (the transport is injected).
struct MyMemoryLanguageModelTests {
    // MARK: - Response parsing

    @Test("parses a valid MyMemory response")
    func parseValidResponse() throws {
        let json = """
        {"responseData":{"translatedText":"Hallo wereld"},"quotaFinished":false}
        """
        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: Data(json.utf8))
        #expect(decoded.responseData.translatedText == "Hallo wereld")
        #expect(decoded.quotaFinished == false)
    }

    @Test("defaults quotaFinished to false when the field is absent")
    func parseMissingQuotaFlag() throws {
        let json = """
        {"responseData":{"translatedText":"Hoi"}}
        """
        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: Data(json.utf8))
        #expect(decoded.quotaFinished == false)
    }

    // MARK: - Error types

    @Test("MyMemoryError has user-friendly descriptions")
    func errorDescriptions() {
        #expect(MyMemoryError.quotaExceeded.errorDescription?.contains("quota") == true)
        #expect(MyMemoryError.requestFailed(statusCode: 500).errorDescription?.contains("500") == true)
        #expect(MyMemoryError.invalidResponse.errorDescription?.contains("unexpected") == true)
    }

    // MARK: - Request building

    @Test("builds a GET to the MyMemory endpoint with the en|nl langpair")
    func buildsRequest() throws {
        let request = try MyMemoryLanguageModel.buildRequest(for: "Hello world")
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://api.mymemory.translated.net/get"))
        #expect(url.contains("langpair=en%7Cnl") || url.contains("langpair=en|nl"))
        #expect(url.contains("q=Hello%20world") || url.contains("q=Hello+world"))
    }

    // MARK: - translate() mapping (transport injected — no network)

    @Test("translates each numbered line and preserves its number")
    func translateMapsByNumber() async throws {
        let model = MyMemoryLanguageModel { request in
            let query = request.url?.query ?? ""
            let translated = query.contains("Hello") ? "Hallo" : "Wereld"
            let json = "{\"responseData\":{\"translatedText\":\"\(translated)\"},\"quotaFinished\":false}"
            return (Data(json.utf8), Self.okResponse)
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

    @Test("a finished daily quota maps to MyMemoryError.quotaExceeded")
    func quotaExceeded() async {
        let model = MyMemoryLanguageModel { _ in
            let json = """
            {"responseData":{"translatedText":""},"quotaFinished":true}
            """
            return (Data(json.utf8), Self.okResponse)
        }
        await #expect(throws: MyMemoryError.quotaExceeded) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("a non-200 status maps to MyMemoryError.requestFailed")
    func httpFailure() async {
        let model = MyMemoryLanguageModel { _ in
            (Data(), Self.response(status: 502))
        }
        await #expect(throws: MyMemoryError.requestFailed(statusCode: 502)) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("is key-free — translate works with no configuration")
    func keyFree() async throws {
        let model = MyMemoryLanguageModel { _ in
            let json = """
            {"responseData":{"translatedText":"Hoi"},"quotaFinished":false}
            """
            return (Data(json.utf8), Self.okResponse)
        }
        let result = try await model.translate([.init(number: 9, text: "Hi")])
        #expect(result == [TranslationLine(number: 9, text: "Hoi")])
    }

    @Test("empty source lines short-circuit without a request")
    func emptyLines() async throws {
        let captured = TransportCapture()
        let model = MyMemoryLanguageModel { request in
            captured.store(request)
            return (Data(), Self.okResponse)
        }
        let result = try await model.translate([])
        #expect(result.isEmpty)
        #expect(captured.wasCalled == false)
    }

    // MARK: - Helpers

    static let okResponse = response(status: 200)

    static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.mymemory.translated.net/get")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
