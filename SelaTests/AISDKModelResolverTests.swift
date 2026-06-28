import Foundation
@testable import Sela
import Testing

struct AISDKModelResolverTests {
    @Test("resolves a Gemini model with a key")
    func resolvesGemini() throws {
        let model = try AISDKModelResolver.model(
            for: .gemini, apiKey: "AIzaTESTKEY", modelID: "gemini-2.5-flash"
        )
        #expect(model.modelId == "gemini-2.5-flash")
    }

    @Test("missing Gemini key throws before any network use")
    func missingKeyThrows() {
        #expect(throws: AISDKModelError.self) {
            _ = try AISDKModelResolver.model(for: .gemini, apiKey: "", modelID: "gemini-2.5-flash")
        }
    }

    @Test("resolves Apple Translation as a key-free on-device custom model when available")
    func resolvesAppleTranslation() throws {
        if #available(macOS 26, *) {
            let model = try AISDKModelResolver.model(for: .apple, apiKey: "", modelID: "")
            #expect(model is AppleTranslationLanguageModel)
        } else {
            // The headless session init needs macOS 26; older hosts get the
            // deferred-error path like a missing key.
            #expect(throws: AISDKModelError.self) {
                _ = try AISDKModelResolver.model(for: .apple, apiKey: "", modelID: "")
            }
        }
    }

    @Test("resolves Apple Intelligence as a key-free on-device custom model")
    func resolvesFoundationModel() throws {
        guard TranslationEngine.isFoundationModelAvailable else {
            // The resolver throws when Apple Intelligence is unavailable; tested below.
            return
        }
        let model = try AISDKModelResolver.model(for: .foundationModel, apiKey: "", modelID: "")
        #expect(model is FoundationModelLanguageModel)
    }

    @Test("resolves Google Translate as a key-free custom model")
    func resolvesGoogleTranslate() throws {
        let model = try AISDKModelResolver.model(for: .googleTranslate, apiKey: "", modelID: "")
        #expect(model is GoogleTranslateLanguageModel)
    }

    @Test("resolves MyMemory as a key-free custom model")
    func resolvesMyMemory() throws {
        let model = try AISDKModelResolver.model(for: .myMemory, apiKey: "", modelID: "")
        #expect(model is MyMemoryLanguageModel)
    }

    @Test("resolves an OpenAI model with a key")
    func resolvesOpenAI() throws {
        let model = try AISDKModelResolver.model(
            for: .openAI, apiKey: "sk-TESTKEY", modelID: "gpt-5-mini"
        )
        #expect(model.modelId == "gpt-5-mini")
    }

    @Test("missing OpenAI key throws before any network use")
    func missingOpenAIKeyThrows() {
        #expect(throws: AISDKModelError.self) {
            _ = try AISDKModelResolver.model(for: .openAI, apiKey: "", modelID: "gpt-5-mini")
        }
    }

    @Test("resolves an Anthropic model with a key")
    func resolvesAnthropic() throws {
        let model = try AISDKModelResolver.model(
            for: .anthropic, apiKey: "sk-ant-TESTKEY", modelID: "claude-sonnet-4-6"
        )
        #expect(model.modelId == "claude-sonnet-4-6")
    }

    @Test("missing Anthropic key throws before any network use")
    func missingAnthropicKeyThrows() {
        #expect(throws: AISDKModelError.self) {
            _ = try AISDKModelResolver.model(for: .anthropic, apiKey: "", modelID: "claude-sonnet-4-6")
        }
    }
}
