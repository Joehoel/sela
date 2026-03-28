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

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                NotificationCenter.default.post(name: .saveSong, object: nil)
            }
            .keyboardShortcut("s")
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
        }
    }
}
