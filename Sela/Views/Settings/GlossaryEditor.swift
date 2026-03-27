import SwiftUI

struct GlossaryEditor: View {
    @State private var terms: [GlossaryEntry] = GlossaryEntry.defaults

    var body: some View {
        VStack {
            Table(terms) {
                TableColumn("English", value: \.source)
                TableColumn("Dutch", value: \.target)
            }

            HStack {
                Button("Add Term") {
                    terms.append(GlossaryEntry(source: "", target: ""))
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

struct GlossaryEntry: Identifiable {
    let id = UUID()
    var source: String
    var target: String

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
