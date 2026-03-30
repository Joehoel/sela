import Foundation
@testable import Sela
import Testing

@MainActor
struct UserPreferencesTests {
    private let testSuiteKey = "test_deeplAPIKey_\(UUID().uuidString)"

    @Test("deeplAPIKey persists to UserDefaults on set")
    func deeplKeyPersists() {
        let prefs = UserPreferences()
        let key = "deeplAPIKey"

        prefs.deeplAPIKey = "test-key-123"

        let stored = UserDefaults.standard.string(forKey: key)
        #expect(stored == "test-key-123")

        // Clean up
        prefs.deeplAPIKey = ""
    }

    @Test("deeplAPIKey loads persisted value on init")
    func deeplKeyLoads() {
        let key = "deeplAPIKey"
        UserDefaults.standard.set("persisted-key", forKey: key)

        let prefs = UserPreferences()

        #expect(prefs.deeplAPIKey == "persisted-key")

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("translationEngine persists to UserDefaults on set")
    func enginePersists() {
        let prefs = UserPreferences()

        prefs.translationEngine = .deepl

        let stored = UserDefaults.standard.string(forKey: "translationEngine")
        #expect(stored == "deepl")

        // Clean up
        prefs.translationEngine = .apple
    }

    @Test("useFoundationModelRefinement persists to UserDefaults on set")
    func refinementTogglePersists() {
        let prefs = UserPreferences()

        prefs.useFoundationModelRefinement = false

        let stored = UserDefaults.standard.bool(forKey: "useFoundationModelRefinement")
        #expect(stored == false)

        // Clean up
        prefs.useFoundationModelRefinement = true
    }

    @Test("deeplAPIKey survives simulated app restart")
    func deeplKeySurvivesRestart() {
        // Simulate first launch: user sets key
        let prefs1 = UserPreferences()
        prefs1.deeplAPIKey = "my-secret-key"

        // Simulate app restart: new instance loads from UserDefaults
        let prefs2 = UserPreferences()
        #expect(prefs2.deeplAPIKey == "my-secret-key")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "deeplAPIKey")
    }

    @Test("deeplAPIKey persists realistic API key strings")
    func deeplKeyPersistsLongStrings() {
        let key = "deeplAPIKey"
        UserDefaults.standard.removeObject(forKey: key)

        let prefs = UserPreferences()

        // Realistic DeepL API key (typically 36-39 chars with special characters)
        let realisticKey = "a1b2c3d4-e5f6-7890-abcd-ef1234567890:fx"
        prefs.deeplAPIKey = realisticKey

        // Verify it persists
        let stored = UserDefaults.standard.string(forKey: key)
        #expect(stored == realisticKey)
        #expect(stored?.count == realisticKey.count)

        // Verify it loads on new instance
        let prefs2 = UserPreferences()
        #expect(prefs2.deeplAPIKey == realisticKey)
        #expect(prefs2.deeplAPIKey.count == realisticKey.count)

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("deeplAPIKey persists when mutated via keypath (like @Bindable)")
    func deeplKeyPersistsViaKeypath() {
        let key = "deeplAPIKey"
        UserDefaults.standard.removeObject(forKey: key)

        let prefs = UserPreferences()
        let keyPath = \UserPreferences.deeplAPIKey

        // Mutate via WritableKeyPath (how @Bindable sets values)
        prefs[keyPath: keyPath] = "keypath-test-value-that-is-quite-long-1234567890"

        let stored = UserDefaults.standard.string(forKey: key)
        #expect(stored == "keypath-test-value-that-is-quite-long-1234567890")

        // Clean up
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("EditorController reads deeplAPIKey from preferences")
    func controllerReadsDeeplKey() {
        let prefs = UserPreferences()
        prefs.deeplAPIKey = "controller-test-key"
        prefs.translationEngine = .deepl

        let song = Song(title: "Test", slideGroups: [
            SlideGroup(name: "V1", slides: [
                Slide(lines: [SlideLine(original: "Hello")]),
            ]),
        ])
        let controller = EditorController(song: song)
        controller.preferences = prefs

        // The controller should read the key from preferences, not fall back to ""
        #expect(controller.preferences?.deeplAPIKey == "controller-test-key")
        #expect(controller.preferences?.translationEngine == .deepl)

        // Clean up
        prefs.deeplAPIKey = ""
        prefs.translationEngine = .apple
    }
}
