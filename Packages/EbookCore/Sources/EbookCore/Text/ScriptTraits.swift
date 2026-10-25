/// Unicode-script helpers that do not assume any particular language.
public enum ScriptTraits {
    /// Coarse writing-system buckets used to judge whether a run of letters is coherent.
    enum Script: Hashable {
        case latin, cyrillic, greek, hebrew, arabic, indic, thai, hangul, cjk, other
    }

    /// Sentence-ending punctuation across scripts (Latin, CJK, Arabic, Urdu, Devanagari, Ethiopic, Armenian).
    private static let sentenceTerminals: Set<Character> = [
        ".", "!", "?", "…", "‼", "⁇", "⁈", "⁉", "。", "！", "？", "．", "؟", "۔", "।", "॥", "።", "։",
    ]

    /// Han ideographs, kana and CJK/fullwidth punctuation: scripts written without spaces between words.
    public static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FA1F: true
            default: false
            }
        }
    }

    public static func isLowercaseLetter(_ c: Character) -> Bool {
        c.isLetter && c.isLowercase
    }

    public static func isSentenceTerminal(_ c: Character) -> Bool {
        sentenceTerminals.contains(c)
    }

    /// Script of a letter, or `nil` if the character is not a letter.
    static func script(of c: Character) -> Script? {
        guard c.isLetter, let scalar = c.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x41...0x24F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xFB00...0xFB06, 0xFF21...0xFF5A: return .latin
        case 0x370...0x3FF, 0x1F00...0x1FFF: return .greek
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: return .cyrillic
        case 0x590...0x5FF: return .hebrew
        case 0x600...0x6FF, 0x750...0x77F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return .arabic
        case 0x900...0xDFF: return .indic
        case 0xE00...0xEFF: return .thai
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return .cjk
        default: return .other
        }
    }
}
