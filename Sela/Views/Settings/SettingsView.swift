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

            DiagnosticSettingsView()
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        }
        .frame(width: 500, height: 450)
    }
}

struct GeneralSettingsView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("ProPresenter Library") {
                HStack {
                    Text(preferences.libraryPath)
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
                Picker("Engine", selection: $preferences.translationEngine) {
                    ForEach(TranslationEngine.allCases, id: \.rawValue) { engine in
                        if engine == .foundationModel, !TranslationEngine.isFoundationModelAvailable {
                            Text(engine.displayName)
                                .tag(engine)
                        } else {
                            Text(engine.displayName).tag(engine)
                        }
                    }
                }

                if !TranslationEngine.isFoundationModelAvailable,
                   preferences.translationEngine == .foundationModel
                {
                    Text("Requires macOS 26 or later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if preferences.translationEngine == .deepl {
                    SecureField("Enter your API key", text: $preferences.deeplAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Link(
                        "Get a free API key at deepl.com",
                        destination: URL(string: "https://www.deepl.com/pro#developer")!
                    )
                    .font(.caption)
                }

                Toggle("Refine with Apple Intelligence", isOn: $preferences.useFoundationModelRefinement)
                    .disabled(
                        preferences.translationEngine == .foundationModel
                            || !TranslationEngine.isFoundationModelAvailable
                    )
                if !TranslationEngine.isFoundationModelAvailable {
                    Text("Requires macOS 26 or later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        panel.directoryURL = URL(fileURLWithPath: (preferences.libraryPath as NSString).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            BookmarkManager.saveBookmark(for: url)
            preferences.libraryPath = url.path
        }
    }
}
