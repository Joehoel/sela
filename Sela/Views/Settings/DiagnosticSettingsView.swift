import SwiftUI

struct DiagnosticSettingsView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        Form {
            Section("Rules") {
                ForEach(DiagnosticRules.all, id: \.id) { rule in
                    Toggle(isOn: binding(for: rule)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                            Text(rule.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding(for rule: any DiagnosticRule) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledRuleIDs.contains(rule.id) },
            set: { enabled in
                if enabled {
                    preferences.enabledRuleIDs.insert(rule.id)
                } else {
                    preferences.enabledRuleIDs.remove(rule.id)
                }
            }
        )
    }
}
