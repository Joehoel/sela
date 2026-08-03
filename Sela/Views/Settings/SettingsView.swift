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
    @Environment(ProPresenterConnection.self) private var connection

    /// Whether the EN→NL Apple Translation pair is installed. Resolved
    /// asynchronously on appear (macOS 26+); Apple Translation only appears in the
    /// engine picker once this is `true`, because the headless session can't
    /// present the download-consent prompt.
    @State private var appleTranslationInstalled = false

    /// Library folders found under the libraries root, shown read-only so the
    /// user can confirm the chosen folder is the right one.
    @State private var discoveredLibraries: [URL] = []

    private var hasDeepLKey: Bool { !preferences.deeplAPIKey.isEmpty }
    private var hasGeminiKey: Bool { !preferences.geminiAPIKey.isEmpty }
    private var hasOpenAIKey: Bool { !preferences.openAIAPIKey.isEmpty }
    private var hasAnthropicKey: Bool { !preferences.anthropicAPIKey.isEmpty }

    private var availableEngines: [TranslationEngine] {
        TranslationEngine.available(
            hasDeepLKey: hasDeepLKey,
            hasGeminiKey: hasGeminiKey,
            hasOpenAIKey: hasOpenAIKey,
            hasAnthropicKey: hasAnthropicKey,
            appleTranslationInstalled: appleTranslationInstalled
        )
    }

    private var availableRefiners: [RefinementEngine] {
        RefinementEngine.available(hasGeminiKey: hasGeminiKey)
    }

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                LabeledContent("Location") {
                    HStack {
                        Text(preferences.librariesRootPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                LabeledContent("Libraries") {
                    if discoveredLibraries.isEmpty {
                        Text("None found")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(discoveredLibraries, id: \.self) { library in
                                Text(library.lastPathComponent)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Libraries")
            } footer: {
                Text("Every subfolder with ProPresenter documents is loaded as a library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Connection", selection: $preferences.proPresenterMode) {
                    ForEach(ProPresenterConnectionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                TextField("Host", text: $preferences.proPresenterHost)
                    .disabled(preferences.proPresenterMode == .automatic)
                    .onSubmit { connection.reconnect() }

                TextField("Port", value: $preferences.proPresenterPort, format: .number.grouping(.never))
                    .disabled(preferences.proPresenterMode == .automatic)
                    .onSubmit { connection.reconnect() }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connection.status.isConnected ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(connection.status.summary)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("ProPresenter")
            } footer: {
                Text("""
                Turn on Enable Network in ProPresenter's Network settings. Automatic tries the last \
                known address, then Bonjour, then the usual localhost ports.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                apiKeyField(
                    title: "OpenAI",
                    text: $preferences.openAIAPIKey,
                    linkTitle: "Get an API key at platform.openai.com",
                    url: "https://platform.openai.com/api-keys"
                )
                apiKeyField(
                    title: "Anthropic",
                    text: $preferences.anthropicAPIKey,
                    linkTitle: "Get an API key at console.anthropic.com",
                    url: "https://console.anthropic.com/settings/keys"
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
        .task { await refreshAppleTranslationAvailability() }
        .task(id: preferences.librariesRootPath) { await refreshDiscoveredLibraries() }
        .onChange(of: appleTranslationInstalled) { _, _ in coerceSelections() }
        .onChange(of: preferences.proPresenterMode) { _, _ in connection.reconnect() }
        .onChange(of: preferences.deeplAPIKey) { _, _ in coerceSelections() }
        .onChange(of: preferences.geminiAPIKey) { _, _ in coerceSelections() }
        .onChange(of: preferences.openAIAPIKey) { _, _ in coerceSelections() }
        .onChange(of: preferences.anthropicAPIKey) { _, _ in coerceSelections() }
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

    /// Resolves whether the EN→NL Apple Translation pair is installed (macOS 26+).
    private func refreshAppleTranslationAvailability() async {
        if #available(macOS 26, *) {
            appleTranslationInstalled = await AppleTranslationLanguageModel.installedLanguagePairAvailable()
        } else {
            appleTranslationInstalled = false
        }
    }

    /// Rescans the libraries root off the main actor — the scan walks the file
    /// system and the root can hold thousands of documents.
    private func refreshDiscoveredLibraries() async {
        let root = URL(fileURLWithPath: (preferences.librariesRootPath as NSString).expandingTildeInPath)
        discoveredLibraries = await Task.detached { LibraryDiscovery.libraries(in: root) }.value
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select ProPresenter Libraries Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (preferences.librariesRootPath as NSString).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            BookmarkManager.saveBookmark(for: url)
            preferences.librariesRootPath = url.path
        }
    }
}

#Preview {
    let preferences = UserPreferences()
    GeneralSettingsView()
        .environment(preferences)
        .environment(ProPresenterConnection(preferences: preferences))
        .frame(width: 500, height: 480)
}
