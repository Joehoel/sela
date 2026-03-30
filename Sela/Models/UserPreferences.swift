import Foundation
import Observation

@Observable @MainActor
final class UserPreferences {
    var translationEngine: TranslationEngine = UserPreferences.loadEngine() {
        didSet {
            UserDefaults.standard.set(translationEngine.rawValue, forKey: "translationEngine")
        }
    }

    var deeplAPIKey: String = UserDefaults.standard.string(forKey: "deeplAPIKey") ?? "" {
        didSet {
            UserDefaults.standard.set(deeplAPIKey, forKey: "deeplAPIKey")
        }
    }

    var libraryPath: String = UserDefaults.standard.string(forKey: "libraryPath")
        ?? "~/Documents/ProPresenter/Libraries/Default"
    {
        didSet {
            UserDefaults.standard.set(libraryPath, forKey: "libraryPath")
        }
    }

    var enabledRuleIDs: Set<String> = UserPreferences.loadEnabledRuleIDs() {
        didSet {
            UserDefaults.standard.set(Array(enabledRuleIDs), forKey: "enabledRuleIDs")
        }
    }

    private static func loadEngine() -> TranslationEngine {
        if let raw = UserDefaults.standard.string(forKey: "translationEngine"),
           let engine = TranslationEngine(rawValue: raw)
        {
            return engine
        }
        return .apple
    }

    private static func loadEnabledRuleIDs() -> Set<String> {
        if let array = UserDefaults.standard.stringArray(forKey: "enabledRuleIDs") {
            return Set(array)
        }
        return Set(DiagnosticRules.defaultEnabledIDs)
    }
}
