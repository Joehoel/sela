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

    /// Folder holding the ProPresenter libraries; every subfolder with `.pro`
    /// files is a library (see `LibraryDiscovery`).
    var librariesRootPath: String {
        didSet {
            defaults.set(librariesRootPath, forKey: "librariesRootPath")
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

    // MARK: - ProPresenter connection

    /// Whether Sela searches for the ProPresenter API or uses a fixed address.
    var proPresenterMode: ProPresenterConnectionMode {
        didSet {
            defaults.set(proPresenterMode.rawValue, forKey: "proPresenterMode")
        }
    }

    /// Host used in manual mode; untouched by auto-discovery.
    var proPresenterHost: String {
        didSet {
            defaults.set(proPresenterHost, forKey: "proPresenterHost")
        }
    }

    /// Port used in manual mode; ProPresenter's default is 1025.
    var proPresenterPort: Int {
        didSet {
            defaults.set(proPresenterPort, forKey: "proPresenterPort")
        }
    }

    /// The last endpoint that answered `GET /version`, tried first in auto mode
    /// so a known ProPresenter is found without waiting for discovery.
    var proPresenterLastKnownEndpoint: ProPresenterEndpoint? {
        didSet {
            defaults.set(proPresenterLastKnownEndpoint?.host, forKey: "proPresenterLastKnownHost")
            defaults.set(proPresenterLastKnownEndpoint?.port, forKey: "proPresenterLastKnownPort")
        }
    }

    /// The manually configured endpoint, or `nil` when it is not usable.
    var proPresenterManualEndpoint: ProPresenterEndpoint? {
        let host = proPresenterHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, (1 ... 65535).contains(proPresenterPort) else { return nil }
        return ProPresenterEndpoint(host: host, port: proPresenterPort)
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

        librariesRootPath = Self.resolveLibrariesRootPath(defaults: defaults)

        proPresenterMode = defaults.string(forKey: "proPresenterMode")
            .flatMap(ProPresenterConnectionMode.init(rawValue:)) ?? .automatic
        proPresenterHost = defaults.string(forKey: "proPresenterHost") ?? Self.defaultProPresenterHost
        let storedPort = defaults.integer(forKey: "proPresenterPort")
        proPresenterPort = storedPort > 0 ? storedPort : Self.defaultProPresenterPort
        proPresenterLastKnownEndpoint = Self.storedEndpoint(defaults: defaults)

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

    // MARK: - Libraries root

    static let defaultLibrariesRootPath = "~/Documents/ProPresenter/Libraries"
    static let defaultProPresenterHost = "localhost"
    static let defaultProPresenterPort = 1025

    /// The persisted last-known endpoint, or `nil` when nothing was stored yet.
    private static func storedEndpoint(defaults: UserDefaults) -> ProPresenterEndpoint? {
        guard let host = defaults.string(forKey: "proPresenterLastKnownHost"), !host.isEmpty else { return nil }
        let port = defaults.integer(forKey: "proPresenterLastKnownPort")
        guard port > 0 else { return nil }
        return ProPresenterEndpoint(host: host, port: port)
    }

    /// The stored libraries root, migrating the pre-multi-library `libraryPath`
    /// (a single library folder) to its parent folder on first run.
    private static func resolveLibrariesRootPath(defaults: UserDefaults) -> String {
        defer { defaults.removeObject(forKey: "libraryPath") }

        if let stored = defaults.string(forKey: "librariesRootPath"), !stored.isEmpty {
            return stored
        }

        if let migrated = migratedLibrariesRootPath(defaults: defaults) {
            defaults.set(migrated, forKey: "librariesRootPath")
            return migrated
        }

        return defaultLibrariesRootPath
    }

    /// The parent of the legacy single-library path, when that path is a folder.
    private static func migratedLibrariesRootPath(defaults: UserDefaults) -> String? {
        guard let legacy = defaults.string(forKey: "libraryPath"), !legacy.isEmpty else { return nil }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: (legacy as NSString).expandingTildeInPath,
            isDirectory: &isDirectory
        )
        guard !exists || isDirectory.boolValue else { return nil }

        let parent = (legacy as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "/" ? nil : parent
    }
}
