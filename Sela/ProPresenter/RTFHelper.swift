import AppKit

enum RTFHelper {
    static func extractText(from rtfData: Data) -> String {
        guard let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
            return ""
        }
        return attributed.string
    }

    static func replaceText(in rtfData: Data, with newText: String) -> Data {
        guard let attributed = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil) else {
            return rtfData
        }
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.replaceCharacters(in: fullRange, with: newText)
        guard let result = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) else {
            return rtfData
        }
        return result
    }
}
