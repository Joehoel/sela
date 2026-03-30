import Foundation
import Observation

@Observable
class Slide: Identifiable {
    let id: String
    var lines: [SlideLine]

    var hasTranslation: Bool {
        lines.contains { !$0.translation.isEmpty }
    }

    init(id: String = UUID().uuidString, lines: [SlideLine]) {
        self.id = id
        self.lines = lines
    }
}
