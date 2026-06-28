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
        .frame(width: 500, height: 480)
    }
}

struct GeneralSettingsView: View {
    @Environment(UserPreferences.self) private var preferences

    private var hasDeepLKey: Bool { !preferences.deeplAPIKey.isEmpty }
    private var hasGeminiKey: Bool { !preferences.geminiAPIKey.isEmpty }

    private var availableEngines: [TranslationEngine] {
        TranslationEngine.available(hasDeepLKey: hasDeepLKey, hasGeminiKey: hasGeminiKey)
    }

    private var availableRefiners: [RefinementEngine] {
        RefinementEngine.available(hasGeminiKey: hasGeminiKey)
    }

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("Library") {
                LabeledContent("Location") {
                    HStack {
                        Text(preferences.libraryPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }
            }

            Section("Translation") {
                Picker("Engine", selection: $preferences.translationEngine) {
                    ForEach(availableEngines, id: \.rawValue) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                modelPicker(
                    models: preferences.translationEngine.availableModels,
                    selection: $preferences.translationModelID,
                    resolved: preferences.resolvedTranslationModel
                )
            }

            Section {
                Picker("Second pass", selection: $preferences.refinementEngine) {
                    Text("None").tag(RefinementEngine?.none)
                    ForEach(availableRefiners, id: \.rawValue) { engine in
                        Text(engine.displayName).tag(RefinementEngine?.some(engine))
                    }
                }
                .disabled(preferences.translationEngine == .foundationModel)

                if let engine = preferences.refinementEngine {
                    modelPicker(
                        models: engine.availableModels,
                        selection: $preferences.refinementModelID,
                        resolved: preferences.resolvedRefinementModel
                    )
                }
            } header: {
                Text("Refinement")
            } footer: {
                Text("""
                Runs a second AI pass after the initial translation to improve natural \
                phrasing, worship-appropriate vocabulary, singability, and reverent \
                register (e.g. “U” instead of “jij”).
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                apiKeyField(
                    title: "DeepL",
                    text: $preferences.deeplAPIKey,
                    linkTitle: "Get a free API key at deepl.com",
                    url: "https://www.deepl.com/pro#developer"
                )
                apiKeyField(
                    title: "Gemini",
                    text: $preferences.geminiAPIKey,
                    linkTitle: "Get a free API key at aistudio.google.com",
                    url: "https://aistudio.google.com/apikey"
                )
            } header: {
                Text("API Keys & Tokens")
            } footer: {
                Text("Providers appear in the menus above once their key is set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { coerceSelections() }
        .onChange(of: preferences.deeplAPIKey) { _, _ in coerceSelections() }
        .onChange(of: preferences.geminiAPIKey) { _, _ in coerceSelections() }
    }

    // MARK: - Reusable rows

    /// A model picker bound to a stored model id, shown only when the provider
    /// offers a choice. Always displays a valid selection via `resolved`.
    @ViewBuilder
    private func modelPicker(
        models: [AIModel],
        selection: Binding<String>,
        resolved: AIModel?
    ) -> some View {
        if !models.isEmpty {
            Picker("Model", selection: Binding(
                get: { resolved?.id ?? models.first?.id ?? "" },
                set: { selection.wrappedValue = $0 }
            )) {
                ForEach(models) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
    }

    @ViewBuilder
    private func apiKeyField(
        title: String,
        text: Binding<String>,
        linkTitle: String,
        url: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
            Link(linkTitle, destination: URL(string: url)!)
                .font(.caption)
        }
    }

    // MARK: - Selection coercion

    /// Keeps the selected engines valid as availability changes (e.g. a key is
    /// removed). Falls back to the first available engine / disables refinement.
    private func coerceSelections() {
        if !availableEngines.contains(preferences.translationEngine),
           let fallback = availableEngines.first
        {
            preferences.translationEngine = fallback
        }
        if let refiner = preferences.refinementEngine, !availableRefiners.contains(refiner) {
            preferences.refinementEngine = nil
        }
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

#Preview {
    GeneralSettingsView()
        .environment(UserPreferences())
        .frame(width: 500, height: 480)
}
