import Foundation
@testable import Sela
import Testing

struct EvalCase: Codable, CustomTestStringConvertible {
    let name: String
    let group: String
    let english: [String]
    let referenceDutch: [String]?

    var testDescription: String {
        name
    }

    func makeItems() -> [TranslationItem] {
        english.enumerated().map { index, line in
            TranslationItem(
                sourceText: line,
                lineID: "\(name)-\(index)",
                groupName: group
            )
        }
    }

    static func loadAll() -> [EvalCase] {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testDir
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/EvalCases.json")
        // swiftlint:disable:next force_try
        let data = try! Data(contentsOf: url)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode([EvalCase].self, from: data)
    }
}
