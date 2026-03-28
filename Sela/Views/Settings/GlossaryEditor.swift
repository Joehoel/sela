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
                        TextField("Correct Dutch", text: $terms[index].target)
                            .textFieldStyle(.plain)
                    }
                }
                TableColumn("Replaces") { entry in
                    if let index = terms.firstIndex(where: { $0.id == entry.id }) {
                        ReplacementTagsView(tags: $terms[index].replacements)
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

private struct ReplacementTagsView: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                TagView(text: tag) {
                    tags.removeAll { $0 == tag }
                }
            }

            TextField("Add…", text: $newTag)
                .textFieldStyle(.plain)
                .frame(minWidth: 40, maxWidth: 60)
                .onSubmit {
                    let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, !tags.contains(trimmed) {
                        tags.append(trimmed)
                    }
                    newTag = ""
                }
        }
    }
}

private struct TagView: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: .capsule)
    }
}

/// A simple wrapping flow layout for inline tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = arrange(subviews: subviews, in: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

struct GlossaryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var source: String
    var target: String
    var replacements: [String]

    init(id: UUID = UUID(), source: String, target: String, replacements: [String] = []) {
        self.id = id
        self.source = source
        self.target = target
        self.replacements = replacements
    }

    private static let storageKey = "glossaryTerms"

    static func load() -> [GlossaryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let terms = try? JSONDecoder().decode([GlossaryEntry].self, from: data)
        else {
            return defaults
        }
        return terms
    }

    static func save(_ terms: [GlossaryEntry]) {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static let defaults: [GlossaryEntry] = [
        GlossaryEntry(source: "You", target: "U", replacements: ["Jij", "Je", "Jou"]),
        GlossaryEntry(source: "Your", target: "Uw", replacements: ["Jouw"]),
        GlossaryEntry(source: "Lord", target: "Heer", replacements: ["Heere", "Here"]),
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
