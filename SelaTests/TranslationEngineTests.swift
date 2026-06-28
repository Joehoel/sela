import Foundation
@testable import Sela
import Testing

struct TranslationEngineTests {
    @Test("only DeepL and Gemini require an API key")
    func requiresAPIKey() {
        #expect(TranslationEngine.deepl.requiresAPIKey)
        #expect(TranslationEngine.gemini.requiresAPIKey)
        #expect(!TranslationEngine.apple.requiresAPIKey)
        #expect(!TranslationEngine.googleTranslate.requiresAPIKey)
        #expect(!TranslationEngine.myMemory.requiresAPIKey)
        #expect(!TranslationEngine.foundationModel.requiresAPIKey)
    }

    @Test("Gemini and DeepL expose models; others do not")
    func availableModels() {
        #expect(!TranslationEngine.gemini.availableModels.isEmpty)
        #expect(!TranslationEngine.deepl.availableModels.isEmpty)
        #expect(TranslationEngine.apple.availableModels.isEmpty)
        #expect(TranslationEngine.googleTranslate.availableModels.isEmpty)
        #expect(TranslationEngine.myMemory.availableModels.isEmpty)
        #expect(TranslationEngine.foundationModel.availableModels.isEmpty)

        // Default is the first model in the catalog.
        #expect(TranslationEngine.gemini.defaultModel?.id == "gemini-2.5-flash")
        #expect(TranslationEngine.deepl.defaultModel?.id == "latency_optimized")
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

    @Test("refinement availability respects the Gemini key")
    func refinementAvailability() {
        #expect(!RefinementEngine.gemini.isAvailable(hasGeminiKey: false))
        #expect(RefinementEngine.gemini.isAvailable(hasGeminiKey: true))
        #expect(RefinementEngine.available(hasGeminiKey: false).contains(.gemini) == false)
    }
}
