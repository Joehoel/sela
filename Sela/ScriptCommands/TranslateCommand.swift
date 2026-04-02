import Cocoa

class TranslateCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let engineName = evaluatedArguments?["withEngine"] as? String
        let scopeParam = evaluatedArguments?["scope"] as? String

        DispatchQueue.main.async {
            guard let appState = SelaApp.shared else { return }

            if let engineName, let engine = TranslationEngine(rawValue: engineName) {
                SelaApp.sharedPreferences?.translationEngine = engine
            }

            appState.translationRequest = scopeParam == "all" ? .allSlides : .emptySlides
        }

        return nil
    }
}
