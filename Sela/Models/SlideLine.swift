import Foundation
import Observation

@Observable
class SlideLine: Identifiable {
    let id: String
    var original: String
    var translation: String

    init(id: String = UUID().uuidString, original: String, translation: String = "") {
        self.id = id
        self.original = original
        self.translation = translation
    }
}
