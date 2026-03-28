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
    @AppStorage("translationEngine") private var selectedEngine = TranslationEngine.apple.rawValue
    @AppStorage("deeplAPIKey") private var deeplAPIKey = ""

    private var engine: TranslationEngine {
        get { TranslationEngine(rawValue: selectedEngine) ?? .apple }
        nonmutating set { selectedEngine = newValue.rawValue }
    }

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

            Section("Translation Engine") {
                Picker("Engine", selection: $selectedEngine) {
                    ForEach(TranslationEngine.allCases, id: \.rawValue) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }

                if engine == .deepl {
                    SecureField("Enter your API key", text: $deeplAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Link(
                        "Get a free API key at deepl.com",
                        destination: URL(string: "https://www.deepl.com/pro#developer")!
                    )
                    .font(.caption)
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
