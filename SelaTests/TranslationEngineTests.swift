import Foundation
@testable import Sela
import Testing

struct TranslationEngineTests {
    @Test("DeepL, Gemini, OpenAI and Anthropic require an API key")
    func requiresAPIKey() {
        #expect(TranslationEngine.deepl.requiresAPIKey)
        #expect(TranslationEngine.gemini.requiresAPIKey)
        #expect(TranslationEngine.openAI.requiresAPIKey)
        #expect(TranslationEngine.anthropic.requiresAPIKey)
        #expect(!TranslationEngine.apple.requiresAPIKey)
        #expect(!TranslationEngine.googleTranslate.requiresAPIKey)
        #expect(!TranslationEngine.myMemory.requiresAPIKey)
        #expect(!TranslationEngine.foundationModel.requiresAPIKey)
    }

    @Test("Gemini, DeepL, OpenAI and Anthropic expose models; others do not")
    func availableModels() {
        #expect(!TranslationEngine.gemini.availableModels.isEmpty)
        #expect(!TranslationEngine.deepl.availableModels.isEmpty)
        #expect(!TranslationEngine.openAI.availableModels.isEmpty)
        #expect(!TranslationEngine.anthropic.availableModels.isEmpty)
        #expect(TranslationEngine.apple.availableModels.isEmpty)
        #expect(TranslationEngine.googleTranslate.availableModels.isEmpty)
        #expect(TranslationEngine.myMemory.availableModels.isEmpty)
        #expect(TranslationEngine.foundationModel.availableModels.isEmpty)

        // Default is the first model in the catalog.
        #expect(TranslationEngine.gemini.defaultModel?.id == "gemini-2.5-flash")
        #expect(TranslationEngine.deepl.defaultModel?.id == "latency_optimized")
        #expect(TranslationEngine.openAI.defaultModel?.id == "gpt-5-mini")
        #expect(TranslationEngine.anthropic.defaultModel?.id == "claude-sonnet-4-6")
    }

    @Test("OpenAI exposes gpt-5-mini and gpt-5")
    func openAICatalog() {
        let ids = TranslationEngine.openAI.availableModels.map(\.id)
        #expect(ids == ["gpt-5-mini", "gpt-5"])
    }

    @Test("Anthropic exposes a Sonnet and a Haiku tier")
    func anthropicCatalog() {
        let ids = TranslationEngine.anthropic.availableModels.map(\.id)
        #expect(ids.contains("claude-sonnet-4-6"))
        #expect(ids.contains("claude-haiku-4-5"))
    }

    @Test("key-gated engines are only available with a key")
    func keyGatedAvailability() {
        #expect(!TranslationEngine.gemini.isAvailable(hasDeepLKey: false, hasGeminiKey: false))
        #expect(TranslationEngine.gemini.isAvailable(hasDeepLKey: false, hasGeminiKey: true))
        #expect(!TranslationEngine.deepl.isAvailable(hasDeepLKey: false, hasGeminiKey: false))
        #expect(TranslationEngine.deepl.isAvailable(hasDeepLKey: true, hasGeminiKey: false))
    }

    @Test("key-free engines are always available")
    func keyFreeAvailability() {
        for engine in [TranslationEngine.googleTranslate, .myMemory] {
            #expect(engine.isAvailable(hasDeepLKey: false, hasGeminiKey: false))
        }
    }

    @Test("available engine list hides key-gated engines without keys")
    func availableEnginesFiltering() {
        let withoutKeys = TranslationEngine.available(hasDeepLKey: false, hasGeminiKey: false)
        #expect(!withoutKeys.contains(.gemini))
        #expect(!withoutKeys.contains(.deepl))
        #expect(withoutKeys.contains(.googleTranslate))
        #expect(withoutKeys.contains(.myMemory))

        let withKeys = TranslationEngine.available(hasDeepLKey: true, hasGeminiKey: true)
        #expect(withKeys.contains(.gemini))
        #expect(withKeys.contains(.deepl))
    }

    @Test("OpenAI and Anthropic are only available with their key")
    func openAIAnthropicAvailability() {
        #expect(!TranslationEngine.openAI.isAvailable(
            hasDeepLKey: false, hasGeminiKey: false, hasOpenAIKey: false, hasAnthropicKey: false
        ))
        #expect(TranslationEngine.openAI.isAvailable(
            hasDeepLKey: false, hasGeminiKey: false, hasOpenAIKey: true, hasAnthropicKey: false
        ))
        #expect(!TranslationEngine.anthropic.isAvailable(
            hasDeepLKey: false, hasGeminiKey: false, hasOpenAIKey: false, hasAnthropicKey: false
        ))
        #expect(TranslationEngine.anthropic.isAvailable(
            hasDeepLKey: false, hasGeminiKey: false, hasOpenAIKey: false, hasAnthropicKey: true
        ))
    }

    @Test("available engine list hides OpenAI and Anthropic without their keys")
    func availableEnginesFilteringLLMs() {
        let withoutKeys = TranslationEngine.available(
            hasDeepLKey: false, hasGeminiKey: false, hasOpenAIKey: false, hasAnthropicKey: false
        )
        #expect(!withoutKeys.contains(.openAI))
        #expect(!withoutKeys.contains(.anthropic))

        let withKeys = TranslationEngine.available(
            hasDeepLKey: false, hasGeminiKey: false, hasOpenAIKey: true, hasAnthropicKey: true
        )
        #expect(withKeys.contains(.openAI))
        #expect(withKeys.contains(.anthropic))
    }

    @Test("Apple Translation is hidden unless macOS 26+ and EN→NL is installed")
    func appleTranslationGating() {
        // The language pair not being installed always hides the engine, even on
        // macOS 26+ (a headless session cannot present the download prompt).
        #expect(!TranslationEngine.apple.isAvailable(
            hasDeepLKey: false, hasGeminiKey: false, appleTranslationInstalled: false
        ))

        // Installed + macOS 26 makes it available; below macOS 26 it stays hidden.
        let availableWhenInstalled = TranslationEngine.apple.isAvailable(
            hasDeepLKey: false, hasGeminiKey: false, appleTranslationInstalled: true
        )
        if #available(macOS 26, *) {
            #expect(availableWhenInstalled)
        } else {
            #expect(!availableWhenInstalled)
        }
    }

    @Test("available engine list includes Apple Translation only when installed (macOS 26+)")
    func availableEnginesAppleGating() {
        let withoutInstall = TranslationEngine.available(
            hasDeepLKey: false, hasGeminiKey: false, appleTranslationInstalled: false
        )
        #expect(!withoutInstall.contains(.apple))

        let withInstall = TranslationEngine.available(
            hasDeepLKey: false, hasGeminiKey: false, appleTranslationInstalled: true
        )
        if #available(macOS 26, *) {
            #expect(withInstall.contains(.apple))
        } else {
            #expect(!withInstall.contains(.apple))
        }
    }

    @Test("refinement availability respects the Gemini key")
    func refinementAvailability() {
        #expect(!RefinementEngine.gemini.isAvailable(hasGeminiKey: false))
        #expect(RefinementEngine.gemini.isAvailable(hasGeminiKey: true))
        #expect(RefinementEngine.available(hasGeminiKey: false).contains(.gemini) == false)
    }
}
