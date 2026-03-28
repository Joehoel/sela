import SwiftUI

struct SelaCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Toggle Diagnose Inspector") {
                appState.isInspectorPresented.toggle()
            }
            .keyboardShortcut("d")
        }

        CommandGroup(after: .textEditing) {
            Button("Translate Empty Slides") {
                appState.translationRequest = .emptySlides
            }
            .keyboardShortcut("t")

            Button("Retranslate All Slides") {
                appState.translationRequest = .allSlides
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Previous Song") {
                navigateSong(direction: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Next Song") {
                navigateSong(direction: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
        }
    }

    private func navigateSong(direction: Int) {
        let songs = appState.filteredSongs
        guard !songs.isEmpty else { return }

        if let currentID = appState.selectedSongID,
           let index = songs.firstIndex(where: { $0.id == currentID })
        {
            let newIndex = min(max(index + direction, 0), songs.count - 1)
            appState.selectedSongID = songs[newIndex].id
        } else {
            appState.selectedSongID = songs.first?.id
        }
    }
}
