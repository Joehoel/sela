import Foundation
import Observation

@Observable
class SlideGroup: Identifiable {
    let id: String
    var name: String
    var slides: [Slide]

    var contentSlides: [Slide] {
        slides.filter(\.hasContent)
    }

    init(id: String = UUID().uuidString, name: String, slides: [Slide] = []) {
        self.id = id
        self.name = name
        self.slides = slides
    }
}
