import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            GlossaryEditor()
                .tabItem {
                    Label("Glossary", systemImage: "book")
                }
        }
        .frame(width: 500, height: 450)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("libraryPath") private var libraryPath = "~/Documents/ProPresenter/Libraries/Default"

    var body: some View {
        Form {
            Section("ProPresenter Library") {
                HStack {
                    Text(libraryPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        chooseFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select ProPresenter Library Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (libraryPath as NSString).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            libraryPath = url.path
        }
    }
}
