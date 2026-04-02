import Cocoa

extension NSApplication {
    @MainActor @objc var scriptSongs: [SelaScriptSong] {
        guard let appState = SelaApp.shared else { return [] }
        return appState.songs.map { SelaScriptSong(song: $0) }
    }

    @MainActor @objc var scriptCurrentSong: SelaScriptSong? {
        guard let appState = SelaApp.shared,
              let song = appState.selectedSong
        else { return nil }
        return SelaScriptSong(song: song)
    }
}
