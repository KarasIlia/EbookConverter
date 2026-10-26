import CoreFoundation
import Foundation

/// Reads the `\info` title and author straight from RTF bytes using the file's declared codepage.
///
/// NSAttributedString may decode `\info` with the wrong 8-bit encoding (e.g. CP1251 read as Mac Cyrillic).
/// This decoder is deterministic: codepage = `\ansicpgN` if valid, else the default font's `\fcharsetN`,
/// else Windows-1252. No guessing.
enum RTFInfoDecoder {
    private static let fallbackCodepage = 1252
    /// `\fcharset` → Windows codepage.
    private static let charsetCodepages: [Int: Int] = [
        0: 1252, 204: 1251, 238: 1250, 161: 1253, 162: 1254, 177: 1255, 178: 1256,
        186: 1257, 222: 874, 128: 932, 134: 936, 129: 949, 136: 950,
    ]

    /// Control words that stand for a character.
    private static let symbolWords: [String: String] = [
        "endash": "–", "emdash": "—", "lquote": "‘", "rquote": "’",
        "ldblquote": "“", "rdblquote": "”", "bullet": "•", "tab": " ",
    ]

    static func metadata(fromRTF data: Data) -> (title: String?, author: String?) {
        let bytes = [UInt8](data)
        guard bytes.starts(with: Array(#"{\rtf"#.utf8)) else { return (nil, nil) }
        var lexer = RTFLexer(bytes: bytes)

        var ansiCodepage: Int?
        var defaultFont = 0
        var fontCharsets: [Int: Int] = [:]
        var fields: [String: [RTFToken]] = [:]

        var depth = 0
        var atGroupStart = false
        var infoDepth: Int?
        var fontTableDepth: Int?
        var currentFont: Int?
        /// The `\title`/`\author` group being collected and its depth.
        var collecting: (field: String, depth: Int)?
        /// Depth of an ignorable `{\* …}` destination nested in a collected field.
        var ignoredDepth: Int?

        while let token = lexer.next() {
            if token == .groupStart {
                depth += 1
                atGroupStart = true
                continue
            }
            if token == .groupEnd {
                if ignoredDepth == depth { ignoredDepth = nil }
                if collecting?.depth == depth { collecting = nil }
                if fontTableDepth == depth { fontTableDepth = nil }
                if infoDepth == depth || depth <= 1 { break }
                depth -= 1
                atGroupStart = false
                continue
            }
            let isGroupHead = atGroupStart
            atGroupStart = false
            if ignoredDepth != nil { continue }

            if isGroupHead {
                if collecting != nil, token == .controlSymbol(UInt8(ascii: "*")) {
                    ignoredDepth = depth
                    continue
                }
                if case .controlWord(let name, _) = token {
                    if name == "info", infoDepth == nil {
                        infoDepth = depth
                        continue
                    }
                    if name == "fonttbl" {
                        fontTableDepth = depth
                        continue
                    }
                    if infoDepth != nil, collecting == nil, name == "title" || name == "author" {
                        collecting = (name, depth)
                        fields[name] = fields[name] ?? []
                        continue
                    }
                }
            }

            if let collecting {
                fields[collecting.field, default: []].append(token)
            } else if fontTableDepth != nil, case .controlWord(let name, let parameter) = token {
                if name == "f" { currentFont = parameter }
                if name == "fcharset", let currentFont, let parameter, fontCharsets[currentFont] == nil {
                    fontCharsets[currentFont] = parameter
                }
            } else if depth == 1, case .controlWord(let name, let parameter) = token {
                if name == "ansicpg", let parameter, encoding(forCodepage: parameter) != nil { ansiCodepage = parameter }
                if name == "deff", let parameter { defaultFont = parameter }
            }
        }

        let codepage = ansiCodepage
            ?? fontCharsets[defaultFont].flatMap { charsetCodepages[$0] }
            ?? fallbackCodepage
        let encoding = encoding(forCodepage: codepage) ?? .windowsCP1252
        return (fields["title"].flatMap { decode($0, encoding: encoding) }, fields["author"].flatMap { decode($0, encoding: encoding) })
    }

    private static func encoding(forCodepage codepage: Int) -> String.Encoding? {
        guard codepage > 0, let value = UInt32(exactly: codepage) else { return nil }
        let cfEncoding = CFStringConvertWindowsCodepageToEncoding(value)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    /// Turns the tokens of a `{\title …}` group into trimmed text, or `nil` if empty.
    private static func decode(_ tokens: [RTFToken], encoding: String.Encoding) -> String? {
        var result = ""
        var pendingBytes: [UInt8] = []
        var pendingUnits: [UInt16] = []
        var fallbackLength = 1
        var skip = 0

        func flushBytes() {
            guard !pendingBytes.isEmpty else { return }
            result += String(bytes: pendingBytes, encoding: encoding) ?? String(decoding: pendingBytes, as: UTF8.self)
            pendingBytes = []
        }
        func flushUnits() {
            guard !pendingUnits.isEmpty else { return }
            result += String(decoding: pendingUnits, as: UTF16.self)
            pendingUnits = []
        }

        for token in tokens {
            // Fallback characters after `\uN` are ANSI substitutes for readers without Unicode support.
            if skip > 0, case .byte = token {
                skip -= 1
                continue
            }
            switch token {
            case .byte(let byte):
                flushUnits()
                pendingBytes.append(byte)
            case .controlWord("u", let parameter?):
                flushBytes()
                pendingUnits.append(UInt16(truncatingIfNeeded: parameter < 0 ? parameter + 65536 : parameter))
                skip = fallbackLength
            case .controlWord("uc", let parameter?):
                fallbackLength = max(parameter, 0)
            case .controlWord(let name, _) where symbolWords[name] != nil:
                flushBytes()
                flushUnits()
                result += symbolWords[name] ?? ""
            case .controlSymbol(UInt8(ascii: "~")):
                flushBytes()
                flushUnits()
                result += "\u{00A0}"
            default:
                break
            }
        }
        flushBytes()
        flushUnits()
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
