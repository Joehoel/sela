import Foundation
@testable import Sela
import Testing

@Suite(.serialized)
struct GlossaryEntryTests {
    @Test("defaults contains expected terms")
    func defaultsNotEmpty() {
        let defaults = GlossaryEntry.defaults
        #expect(defaults.count == 10)
        #expect(defaults.first?.source == "Lord")
        #expect(defaults.first?.target == "Heer")
    }

    @Test("save and load round-trips")
    func saveAndLoad() {
        let key = "glossaryTerms"
        let original = UserDefaults.standard.data(forKey: key)
        defer { // restore original state
            if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let terms = [
            GlossaryEntry(source: "test", target: "proef"),
            GlossaryEntry(source: "word", target: "woord"),
        ]
        GlossaryEntry.save(terms)

        let loaded = GlossaryEntry.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].source == "test")
        #expect(loaded[0].target == "proef")
        #expect(loaded[1].source == "word")
        #expect(loaded[1].target == "woord")
    }

    @Test("load returns defaults when storage is empty")
    func loadReturnsDefaults() {
        let key = "glossaryTerms"
        let original = UserDefaults.standard.data(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        let loaded = GlossaryEntry.load()
        #expect(loaded.count == 10)
        #expect(loaded.first?.source == "Lord")
    }

    @Test("removing a term persists correctly")
    func removeAndPersist() {
        let key = "glossaryTerms"
        let original = UserDefaults.standard.data(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        var terms = [
            GlossaryEntry(source: "one", target: "een"),
            GlossaryEntry(source: "two", target: "twee"),
            GlossaryEntry(source: "three", target: "drie"),
        ]
        let removeID = terms[1].id
        terms.removeAll { $0.id == removeID }
        GlossaryEntry.save(terms)

        let loaded = GlossaryEntry.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].source == "one")
        #expect(loaded[1].source == "three")
        #expect(!loaded.contains { $0.id == removeID })
    }

    @Test("removing all terms persists empty list")
    func removeAllPersistsEmpty() {
        let key = "glossaryTerms"
        let original = UserDefaults.standard.data(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }

        GlossaryEntry.save([])
        let loaded = GlossaryEntry.load()
        #expect(loaded.isEmpty)
    }
}
