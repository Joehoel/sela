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
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("ProPresenter Library") {
                HStack {
                    Text("~/Documents/ProPresenter/Libraries/Default")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose...") {
                        // Placeholder — will use NSOpenPanel
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
