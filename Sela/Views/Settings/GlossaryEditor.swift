import SwiftUI

struct GlossaryEditor: View {
    @State private var terms: [GlossaryEntry] = GlossaryEntry.load()
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Table(of: GlossaryEntry.self, selection: $selection) {
                TableColumn("English") { entry in
                    if let index = terms.firstIndex(where: { $0.id == entry.id }) {
                        TextField("English term", text: $terms[index].source)
                            .textFieldStyle(.plain)
                    }
                }
                TableColumn("Dutch") { entry in
                    if let index = terms.firstIndex(where: { $0.id == entry.id }) {
                        TextField("Dutch translation", text: $terms[index].target)
                            .textFieldStyle(.plain)
                    }
                }
            } rows: {
                ForEach(terms) { term in
                    TableRow(term)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    let newTerm = GlossaryEntry(source: "", target: "")
                    terms.append(newTerm)
                    selection = [newTerm.id]
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    terms.removeAll { selection.contains($0.id) }
                    selection = []
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty)

                Spacer()

                Text("\(terms.count) terms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onChange(of: terms) {
            GlossaryEntry.save(terms)
        }
    }
}

struct GlossaryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var source: String
    var target: String

    init(id: UUID = UUID(), source: String, target: String) {
        self.id = id
        self.source = source
        self.target = target
    }

    private static let storageKey = "glossaryTerms"

    static func load() -> [GlossaryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let terms = try? JSONDecoder().decode([GlossaryEntry].self, from: data) else {
            return defaults
        }
        return terms
    }

    static func save(_ terms: [GlossaryEntry]) {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static let defaults: [GlossaryEntry] = [
        GlossaryEntry(source: "Lord", target: "Heer"),
        GlossaryEntry(source: "grace", target: "genade"),
        GlossaryEntry(source: "soul", target: "ziel"),
        GlossaryEntry(source: "praise", target: "lofprijs"),
        GlossaryEntry(source: "worship", target: "aanbidding"),
        GlossaryEntry(source: "holy", target: "heilig"),
        GlossaryEntry(source: "mercy", target: "barmhartigheid"),
        GlossaryEntry(source: "salvation", target: "verlossing"),
        GlossaryEntry(source: "righteousness", target: "gerechtigheid"),
        GlossaryEntry(source: "heaven", target: "hemel"),
    ]
}
