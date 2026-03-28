import Foundation
import Observation

@Observable
class Slide: Identifiable {
    let id: String
    var lines: [SlideLine]
    var isTranslatable: Bool

    var hasTranslation: Bool {
        lines.contains { !$0.translation.isEmpty }
    }

    init(id: String = UUID().uuidString, lines: [SlideLine], isTranslatable: Bool = false) {
        self.id = id
        self.lines = lines
        self.isTranslatable = isTranslatable
    }
}
