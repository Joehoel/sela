import Foundation

/// Lightweight RTF-to-plain-text extractor used on the library-load hot path.
///
/// `NSAttributedString(rtf:)` is too heavy when invoked hundreds of thousands
/// of times while scanning a large ProPresenter library — it allocates fonts,
/// colors, and attribute dictionaries per call. This stripper handles the
/// ProPresenter RTF shape directly (fonttbl, colortbl, basic text with
/// `\par`/`\line`/`\'xx`/`\uNNNN`) and is safe to call from any thread.
///
/// For writing (where formatting must be preserved round-trip), `RTFHelper`
/// still uses `NSAttributedString`.
enum RTFTextStripper {
    /// Destinations whose contents should be discarded entirely.
    private static let skipDestinations: Set<String> = [
        "fonttbl", "colortbl", "stylesheet", "info", "pict",
        "object", "header", "footer", "headerf", "footerf",
        "author", "title", "subject", "company", "operator",
        "creatim", "revtim", "printim", "buptim",
        "comment", "doccomm", "keywords", "doctype",
        "listtable", "listoverridetable", "rsidtbl", "revtbl",
        "generator", "xmlnstbl", "shppict", "nonshppict",
        "pntxta", "pntxtb", "pn", "pntext",
        "latentstyles", "lsdlockedexcept", "datafield",
        "fldinst", "fldrslt", "themedata", "colorschememapping",
        "datastore", "wgrffmtfilter", "mmathPr", "mmathFont",
    ]

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func extractText(from rtfData: Data) -> String {
        let bytes = [UInt8](rtfData)
        let len = bytes.count
        var text = ""
        text.reserveCapacity(len / 4)

        var groupStack: [Bool] = []
        var skipping = false
        var i = 0

        parseLoop: while i < len {
            let byte = bytes[i]
            switch byte {
            case 0x7B: // {
                groupStack.append(skipping)
                i += 1
                if i < len, bytes[i] == 0x5C {
                    let afterBS = i + 1
                    if afterBS < len {
                        let nc = bytes[afterBS]
                        if nc == 0x2A {
                            // {\* — ignorable destination
                            skipping = true
                        } else if Self.isLetter(nc) {
                            let (name, _) = Self.parseControlName(bytes, from: afterBS)
                            if skipDestinations.contains(name) {
                                skipping = true
                            }
                        }
                    }
                }

            case 0x7D: // }
                skipping = groupStack.popLast() ?? false
                i += 1
                if groupStack.isEmpty {
                    // The outermost group has closed — the RTF document is
                    // complete. Any trailing bytes are not part of the
                    // document per spec, so stop here. Some ProPresenter
                    // exports append stray text after the final }; we match
                    // NSAttributedString and ignore it.
                    break parseLoop
                }

            case 0x5C: // \
                i += 1
                guard i < len else { break }
                let nc = bytes[i]
                if nc == 0x5C || nc == 0x7B || nc == 0x7D {
                    // Escaped backslash or brace
                    if !skipping { text.unicodeScalars.append(Unicode.Scalar(nc)) }
                    i += 1
                } else if nc == 0x27 { // '
                    // \'xx — hex byte escape, interpreted as Windows-1252
                    guard i + 2 < len,
                          let hi = Self.hexValue(bytes[i + 1]),
                          let lo = Self.hexValue(bytes[i + 2])
                    else {
                        i = min(i + 3, len)
                        break
                    }
                    i += 3
                    if !skipping {
                        let value = UInt8(hi * 16 + lo)
                        if let scalar = Self.windowsCP1252Scalar(value) {
                            text.unicodeScalars.append(scalar)
                        }
                    }
                } else if Self.isLetter(nc) {
                    // \u Unicode escape: \uNNNN<fallback>
                    if nc == 0x75,
                       i + 1 < len,
                       Self.isDigit(bytes[i + 1]) || bytes[i + 1] == 0x2D
                    {
                        var j = i + 1
                        var negative = false
                        if bytes[j] == 0x2D {
                            negative = true
                            j += 1
                        }
                        var value = 0
                        while j < len, Self.isDigit(bytes[j]) {
                            value = value * 10 + Int(bytes[j] - 0x30)
                            j += 1
                        }
                        var codepoint = negative ? -value : value
                        if codepoint < 0 { codepoint += 0x10000 }
                        if !skipping, codepoint > 0,
                           let scalar = Unicode.Scalar(codepoint)
                        {
                            text.unicodeScalars.append(scalar)
                        }
                        i = j
                        if i < len, bytes[i] == 0x20 { i += 1 }
                        // Skip one fallback token (\ucN defaults to 1).
                        if i < len {
                            let fb = bytes[i]
                            if fb == 0x5C, i + 1 < len {
                                let after = bytes[i + 1]
                                if after == 0x27, i + 4 <= len {
                                    i += 4
                                } else if Self.isLetter(after) {
                                    let (_, next) = Self.parseControlName(bytes, from: i + 1)
                                    i = next
                                    if i < len, bytes[i] == 0x20 { i += 1 }
                                } else {
                                    i += 2
                                }
                            } else if fb != 0x7B, fb != 0x7D {
                                i += 1
                            }
                        }
                        continue
                    }

                    let (name, afterWord) = Self.parseControlName(bytes, from: i)
                    i = afterWord
                    if !skipping {
                        switch name {
                        case "par", "line", "sect", "page":
                            text.append("\n")
                        case "tab":
                            text.append("\t")
                        case "emdash":
                            text.unicodeScalars.append("\u{2014}")
                        case "endash":
                            text.unicodeScalars.append("\u{2013}")
                        case "lquote":
                            text.unicodeScalars.append("\u{2018}")
                        case "rquote":
                            text.unicodeScalars.append("\u{2019}")
                        case "ldblquote":
                            text.unicodeScalars.append("\u{201C}")
                        case "rdblquote":
                            text.unicodeScalars.append("\u{201D}")
                        case "bullet":
                            text.unicodeScalars.append("\u{2022}")
                        default:
                            break
                        }
                    }
                    // Optional single-space delimiter after a control word is consumed.
                    if i < len, bytes[i] == 0x20 { i += 1 }
                } else {
                    // Control symbol (e.g. \~, \-, \_)
                    if !skipping {
                        switch nc {
                        case 0x7E: // ~ — non-breaking space
                            text.append(" ")
                        case 0x5F: // _ — non-breaking hyphen
                            text.unicodeScalars.append("\u{2011}")
                        default:
                            break
                        }
                    }
                    i += 1
                }

            case 0x0A, 0x0D:
                // Raw newlines in source RTF are not part of the text content.
                i += 1

            default:
                if !skipping {
                    text.unicodeScalars.append(Unicode.Scalar(byte))
                }
                i += 1
            }
        }

        return text
    }

    // MARK: - Byte helpers

    private static func parseControlName(_ bytes: [UInt8], from start: Int) -> (String, Int) {
        var i = start
        let len = bytes.count
        while i < len, isLetter(bytes[i]) {
            i += 1
        }
        // Control word bytes are always ASCII per RTF spec.
        let name = String(bytes: bytes[start ..< i], encoding: .ascii) ?? ""
        if i < len, bytes[i] == 0x2D { i += 1 }
        while i < len, isDigit(bytes[i]) {
            i += 1
        }
        return (name, i)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 0x30 ... 0x39: Int(byte - 0x30)
        case 0x61 ... 0x66: Int(byte - 0x61 + 10)
        case 0x41 ... 0x46: Int(byte - 0x41 + 10)
        default: nil
        }
    }

    /// Windows-1252 → Unicode. 0x00–0x7F and 0xA0–0xFF map identity; the
    /// 0x80–0x9F range carries the Windows-specific extras (€, smart quotes,
    /// em/en dash, etc.).
    private static func windowsCP1252Scalar(_ byte: UInt8) -> Unicode.Scalar? {
        if byte < 0x80 || byte >= 0xA0 {
            return Unicode.Scalar(byte)
        }
        let table: [UInt32?] = [
            0x20AC, nil, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
            0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, nil, 0x017D, nil,
            nil, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
            0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, nil, 0x017E, 0x0178,
        ]
        let idx = Int(byte) - 0x80
        guard idx >= 0, idx < table.count, let value = table[idx] else {
            return nil
        }
        return Unicode.Scalar(value)
    }
}
