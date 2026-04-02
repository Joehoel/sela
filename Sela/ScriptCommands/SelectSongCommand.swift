import Cocoa

class SelectSongCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let title = directParameter as? String else { return nil }

        DispatchQueue.main.async {
            guard let appState = SelaApp.shared else { return }
            appState.selectedSongID = appState.songs.first {
                $0.title.localizedCaseInsensitiveContains(title)
            }?.id
        }

        return nil
    }
}
