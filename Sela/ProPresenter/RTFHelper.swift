import AppKit

enum RTFHelper {
    static func extractText(from rtfData: Data) -> String {
        guard let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
            return ""
        }
        return attributed.string
    }

    /// Replaces the text of `rtfData` with `newText`, keeping the original
    /// formatting.
    ///
    /// When the target has no characters to inherit from — e.g. an empty
    /// pre-made translation box — `replaceCharacters` would give the new text
    /// system-default attributes (Helvetica 12, black, left-aligned), silently
    /// dropping the box's intended font, size, color, and alignment. In that
    /// case the look is borrowed from `formattingSource` (typically the
    /// original-language box on the same slide) instead.
    static func replaceText(in rtfData: Data, with newText: String, formattingSource: Data? = nil) -> Data {
        guard let attributed = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil) else {
            return rtfData
        }

        if attributed.length == 0,
           let source = formattingSource,
           let template = NSAttributedString(rtf: source, documentAttributes: nil),
           template.length > 0
        {
            let attributes = template.attributes(at: 0, effectiveRange: nil)
            let styled = NSAttributedString(string: newText, attributes: attributes)
            guard let result = styled.rtf(from: NSRange(location: 0, length: styled.length), documentAttributes: [:]) else {
                return rtfData
            }
            return result
        }

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.replaceCharacters(in: fullRange, with: newText)
        guard let result = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) else {
            return rtfData
        }
        return result
    }
}
