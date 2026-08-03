import Foundation
@testable import Sela
import Testing

@MainActor
struct UserPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("deeplAPIKey persists to UserDefaults on set")
    func deeplKeyPersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.deeplAPIKey = "test-key-123"

        #expect(defaults.string(forKey: "deeplAPIKey") == "test-key-123")
    }

    @Test("deeplAPIKey loads persisted value on init")
    func deeplKeyLoads() {
        let defaults = makeDefaults()
        defaults.set("persisted-key", forKey: "deeplAPIKey")

        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.deeplAPIKey == "persisted-key")
    }

    @Test("deeplAPIKey survives simulated app restart")
    func deeplKeySurvivesRestart() {
        let defaults = makeDefaults()
        let prefs1 = UserPreferences(defaults: defaults)
        prefs1.deeplAPIKey = "my-secret-key"

        let prefs2 = UserPreferences(defaults: defaults)
        #expect(prefs2.deeplAPIKey == "my-secret-key")
    }

    @Test("deeplAPIKey persists realistic API key strings")
    func deeplKeyPersistsLongStrings() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        let realisticKey = "a1b2c3d4-e5f6-7890-abcd-ef1234567890:fx"
        prefs.deeplAPIKey = realisticKey

        #expect(defaults.string(forKey: "deeplAPIKey") == realisticKey)

        let prefs2 = UserPreferences(defaults: defaults)
        #expect(prefs2.deeplAPIKey == realisticKey)
        #expect(prefs2.deeplAPIKey.count == realisticKey.count)
    }

    @Test("openAIAPIKey persists and survives restart")
    func openAIKeyPersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.openAIAPIKey = "sk-openai-123"
        #expect(defaults.string(forKey: "openAIAPIKey") == "sk-openai-123")

        let prefs2 = UserPreferences(defaults: defaults)
        #expect(prefs2.openAIAPIKey == "sk-openai-123")
    }

    @Test("anthropicAPIKey persists and survives restart")
    func anthropicKeyPersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.anthropicAPIKey = "sk-ant-123"
        #expect(defaults.string(forKey: "anthropicAPIKey") == "sk-ant-123")

        let prefs2 = UserPreferences(defaults: defaults)
        #expect(prefs2.anthropicAPIKey == "sk-ant-123")
    }

    @Test("resolvedTranslationModel resolves an OpenAI selection")
    func resolvedModelOpenAI() {
        let prefs = UserPreferences(defaults: makeDefaults())
        prefs.translationEngine = .openAI
        prefs.translationModelID = "gpt-5"
        #expect(prefs.resolvedTranslationModel?.id == "gpt-5")
    }

    @Test("resolvedTranslationModel falls back to the Anthropic default for a bad selection")
    func resolvedModelAnthropicFallback() {
        let prefs = UserPreferences(defaults: makeDefaults())
        prefs.translationEngine = .anthropic
        prefs.translationModelID = "gpt-5" // not an Anthropic id
        #expect(prefs.resolvedTranslationModel?.id == TranslationEngine.anthropic.defaultModel?.id)
    }

    @Test("translationEngine persists to UserDefaults on set")
    func enginePersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.translationEngine = .deepl

        #expect(defaults.string(forKey: "translationEngine") == "deepl")
    }

    @Test("refinementEngine persists to UserDefaults on set")
    func refinementEnginePersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.refinementEngine = .gemini

        #expect(defaults.string(forKey: "refinementEngine") == "gemini")
    }

    @Test("refinementEngine migrates from old boolean preference")
    func refinementEngineMigration() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "useFoundationModelRefinement")
        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.refinementEngine == .foundationModel)
    }

    @Test("refinementEngine migrates to nil when old boolean was false")
    func refinementEngineMigrationDisabled() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "useFoundationModelRefinement")
        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.refinementEngine == nil)
    }

    @Test("translationModelID persists and survives restart")
    func translationModelPersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.translationModelID = "gemini-2.5-pro"
        #expect(defaults.string(forKey: "translationModelID") == "gemini-2.5-pro")

        let prefs2 = UserPreferences(defaults: defaults)
        #expect(prefs2.translationModelID == "gemini-2.5-pro")
    }

    @Test("resolvedTranslationModel returns the stored model when valid for the engine")
    func resolvedModelHonoursSelection() {
        let prefs = UserPreferences(defaults: makeDefaults())
        prefs.translationEngine = .gemini
        prefs.translationModelID = "gemini-2.5-pro"
        #expect(prefs.resolvedTranslationModel?.id == "gemini-2.5-pro")
    }

    @Test("resolvedTranslationModel falls back to the default for a mismatched selection")
    func resolvedModelFallsBack() {
        let prefs = UserPreferences(defaults: makeDefaults())
        prefs.translationEngine = .gemini
        // A DeepL model id is not valid for Gemini — should fall back to default.
        prefs.translationModelID = "quality_optimized"
        #expect(prefs.resolvedTranslationModel?.id == TranslationEngine.gemini.defaultModel?.id)
    }

    @Test("resolvedTranslationModel is nil for engines without models")
    func resolvedModelNilForModellessEngine() {
        let prefs = UserPreferences(defaults: makeDefaults())
        prefs.translationEngine = .apple
        #expect(prefs.resolvedTranslationModel == nil)
    }

    @Test("resolvedRefinementModel resolves against the refinement engine")
    func resolvedRefinementModel() {
        let prefs = UserPreferences(defaults: makeDefaults())
        prefs.refinementEngine = .gemini
        prefs.refinementModelID = "gemini-3.1-pro-preview"
        #expect(prefs.resolvedRefinementModel?.id == "gemini-3.1-pro-preview")

        prefs.refinementEngine = nil
        #expect(prefs.resolvedRefinementModel == nil)
    }

    @Test("librariesRootPath defaults to the ProPresenter Libraries folder")
    func librariesRootDefault() {
        let prefs = UserPreferences(defaults: makeDefaults())
        #expect(prefs.librariesRootPath == "~/Documents/ProPresenter/Libraries")
    }

    @Test("librariesRootPath migrates the old single-library path to its parent")
    func librariesRootMigratesFromLibraryPath() throws {
        let defaults = makeDefaults()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sela-prefs-\(UUID().uuidString)/Libraries", isDirectory: true)
        let library = root.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        defaults.set(library.path, forKey: "libraryPath")

        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.librariesRootPath == root.path)
        #expect(defaults.string(forKey: "librariesRootPath") == root.path)
        #expect(defaults.string(forKey: "libraryPath") == nil)
    }

    @Test("librariesRootPath migration keeps the tilde form of the old path")
    func librariesRootMigrationKeepsTilde() {
        let defaults = makeDefaults()
        defaults.set("~/Documents/ProPresenter/Libraries/Default", forKey: "libraryPath")

        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.librariesRootPath == "~/Documents/ProPresenter/Libraries")
    }

    @Test("librariesRootPath ignores the old key once a root is stored")
    func librariesRootPrefersStoredValue() {
        let defaults = makeDefaults()
        defaults.set("/Volumes/Media/Libraries", forKey: "librariesRootPath")
        defaults.set("/Volumes/Media/Libraries/Default", forKey: "libraryPath")

        let prefs = UserPreferences(defaults: defaults)

        #expect(prefs.librariesRootPath == "/Volumes/Media/Libraries")
        #expect(defaults.string(forKey: "libraryPath") == nil)
    }

    @Test("librariesRootPath persists and survives restart")
    func librariesRootPersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.librariesRootPath = "/Volumes/Media/Libraries"

        #expect(defaults.string(forKey: "librariesRootPath") == "/Volumes/Media/Libraries")
        #expect(UserPreferences(defaults: defaults).librariesRootPath == "/Volumes/Media/Libraries")
    }

    // MARK: - ProPresenter connection

    @Test("the ProPresenter connection defaults to automatic on localhost:1025")
    func proPresenterDefaults() {
        let prefs = UserPreferences(defaults: makeDefaults())

        #expect(prefs.proPresenterMode == .automatic)
        #expect(prefs.proPresenterHost == "localhost")
        #expect(prefs.proPresenterPort == 1025)
        #expect(prefs.proPresenterLastKnownEndpoint == nil)
    }

    @Test("manual ProPresenter settings survive a restart")
    func proPresenterManualSettingsPersist() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.proPresenterMode = .manual
        prefs.proPresenterHost = "10.0.0.5"
        prefs.proPresenterPort = 50727

        let restarted = UserPreferences(defaults: defaults)
        #expect(restarted.proPresenterMode == .manual)
        #expect(restarted.proPresenterManualEndpoint == ProPresenterEndpoint(host: "10.0.0.5", port: 50727))
    }

    @Test("an empty host or an impossible port leaves no manual endpoint")
    func proPresenterManualEndpointValidation() {
        let prefs = UserPreferences(defaults: makeDefaults())

        prefs.proPresenterHost = ""
        #expect(prefs.proPresenterManualEndpoint == nil)

        prefs.proPresenterHost = "localhost"
        prefs.proPresenterPort = 0
        #expect(prefs.proPresenterManualEndpoint == nil)
    }

    @Test("enabledRuleIDs persists to UserDefaults on set")
    func ruleIDsPersist() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.enabledRuleIDs = ["ruleA", "ruleB"]

        let stored = Set(defaults.stringArray(forKey: "enabledRuleIDs") ?? [])
        #expect(stored == ["ruleA", "ruleB"])
    }

    @Test("EditorController reads deeplAPIKey from preferences")
    func controllerReadsDeeplKey() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.deeplAPIKey = "controller-test-key"
        prefs.translationEngine = .deepl

        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "V1", slides: [
                Slide(lines: [SlideLine(original: "Hello")]),
            ]),
        ])
        let controller = EditorController(song: song)
        controller.preferences = prefs

        #expect(controller.preferences?.deeplAPIKey == "controller-test-key")
        #expect(controller.preferences?.translationEngine == .deepl)
    }
}
