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

    var libraryPath: String {
        didSet {
            defaults.set(libraryPath, forKey: "libraryPath")
        }
    }

    var useFoundationModelRefinement: Bool {
        didSet {
            defaults.set(useFoundationModelRefinement, forKey: "useFoundationModelRefinement")
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

        libraryPath = defaults.string(forKey: "libraryPath")
            ?? "~/Documents/ProPresenter/Libraries/Default"

        useFoundationModelRefinement = defaults.object(forKey: "useFoundationModelRefinement") as? Bool ?? true

        if let array = defaults.stringArray(forKey: "enabledRuleIDs") {
            enabledRuleIDs = Set(array)
        } else {
            enabledRuleIDs = Set(DiagnosticRules.defaultEnabledIDs)
        }
    }
}
