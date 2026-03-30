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

    @Test("translationEngine persists to UserDefaults on set")
    func enginePersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.translationEngine = .deepl

        #expect(defaults.string(forKey: "translationEngine") == "deepl")
    }

    @Test("useFoundationModelRefinement persists to UserDefaults on set")
    func refinementTogglePersists() {
        let defaults = makeDefaults()
        let prefs = UserPreferences(defaults: defaults)

        prefs.useFoundationModelRefinement = false

        #expect(defaults.bool(forKey: "useFoundationModelRefinement") == false)
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
