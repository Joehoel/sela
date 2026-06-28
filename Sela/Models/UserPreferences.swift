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

    var openAIAPIKey: String {
        didSet {
            defaults.set(openAIAPIKey, forKey: "openAIAPIKey")
        }
    }

    var anthropicAPIKey: String {
        didSet {
            defaults.set(anthropicAPIKey, forKey: "anthropicAPIKey")
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

    /// Selected model id for the translation engine (empty = use the engine's
    /// default). Interpreted via `resolvedTranslationModel`.
    var translationModelID: String {
        didSet {
            defaults.set(translationModelID, forKey: "translationModelID")
        }
    }

    /// Selected model id for the refinement engine (empty = use its default).
    var refinementModelID: String {
        didSet {
            defaults.set(refinementModelID, forKey: "refinementModelID")
        }
    }

    /// The model to use for translation: the stored selection when it's valid
    /// for the current engine, otherwise the engine's default. `nil` when the
    /// engine has no model selection.
    var resolvedTranslationModel: AIModel? {
        let models = translationEngine.availableModels
        return models.first { $0.id == translationModelID } ?? translationEngine.defaultModel
    }

    /// The model to use for refinement, resolved like `resolvedTranslationModel`.
    var resolvedRefinementModel: AIModel? {
        guard let engine = refinementEngine else { return nil }
        let models = engine.availableModels
        return models.first { $0.id == refinementModelID } ?? engine.defaultModel
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
        openAIAPIKey = defaults.string(forKey: "openAIAPIKey") ?? ""
        anthropicAPIKey = defaults.string(forKey: "anthropicAPIKey") ?? ""

        translationModelID = defaults.string(forKey: "translationModelID") ?? ""
        refinementModelID = defaults.string(forKey: "refinementModelID") ?? ""

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
