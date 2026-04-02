import Foundation
import Observation

@Observable @MainActor
final class UserPreferences {
    private let defaults: UserDefaults

    var translationEngine: TranslationEngine {
        didSet {
            defaults.set(translationEngine.rawValue, forKey: "translationEngine")
        }
    }

    var deeplAPIKey: String {
        didSet {
            defaults.set(deeplAPIKey, forKey: "deeplAPIKey")
        }
    }

    var geminiAPIKey: String {
        didSet {
            defaults.set(geminiAPIKey, forKey: "geminiAPIKey")
        }
    }

    var libraryPath: String {
        didSet {
            defaults.set(libraryPath, forKey: "libraryPath")
        }
    }

    var refinementEngine: RefinementEngine? {
        didSet {
            defaults.set(refinementEngine?.rawValue, forKey: "refinementEngine")
        }
    }

    var enabledRuleIDs: Set<String> {
        didSet {
            defaults.set(Array(enabledRuleIDs), forKey: "enabledRuleIDs")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: "translationEngine"),
           let engine = TranslationEngine(rawValue: raw)
        {
            translationEngine = engine
        } else {
            translationEngine = .apple
        }

        deeplAPIKey = defaults.string(forKey: "deeplAPIKey") ?? ""
        geminiAPIKey = defaults.string(forKey: "geminiAPIKey") ?? ""

        libraryPath = defaults.string(forKey: "libraryPath")
            ?? "~/Documents/ProPresenter/Libraries/Default"

        // Migrate from old boolean preference to new enum
        if let raw = defaults.string(forKey: "refinementEngine") {
            refinementEngine = RefinementEngine(rawValue: raw)
        } else if defaults.object(forKey: "useFoundationModelRefinement") as? Bool ?? true {
            refinementEngine = .foundationModel
        } else {
            refinementEngine = nil
        }

        if let array = defaults.stringArray(forKey: "enabledRuleIDs") {
            enabledRuleIDs = Set(array)
        } else {
            enabledRuleIDs = Set(DiagnosticRules.defaultEnabledIDs)
        }
    }
}
