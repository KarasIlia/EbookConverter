import Foundation

/// Repairs text that was decoded with the wrong legacy encoding (e.g. Mac Cyrillic text read as Windows-1251).
///
/// Each candidate pair re-encodes the string with the encoding it was wrongly decoded as and decodes the
/// bytes with the encoding they were likely written in. A candidate is accepted only if it is clearly more
/// coherent than the original (see `score`).
public enum MojibakeRepair {
    private static let macCyrillic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.macCyrillic.rawValue)))

    /// (encode as, decode as)
    private static let candidates: [(String.Encoding, String.Encoding)] = [
        (macCyrillic, .windowsCP1251),
        (.macOSRoman, .windowsCP1252),
        (.macOSRoman, .windowsCP1251),
        (.isoLatin1, .windowsCP1251),
        (.isoLatin1, .windowsCP1250),
        (.windowsCP1252, .utf8),
    ]

    /// Minimum score gain for a candidate to be accepted.
    private static let requiredGain = 0.3
    /// A fully coherent candidate is accepted with a smaller gain, because a single damaged word in a
    /// short string (`’очу в программисты! ќсновы`) moves the share of coherent words only slightly.
    private static let requiredGainForCleanResult = 0.2
    private static let minimumLettersForCleanResult = 8

    public static func repair(_ s: String) -> String {
        guard s.contains(where: { !$0.isASCII }) else { return s }
        let original = score(s)
        var best: (text: String, score: Double, letters: Int)?
        for (encodeAs, decodeAs) in candidates {
            guard let data = s.data(using: encodeAs),
                  let text = String(data: data, encoding: decodeAs),
                  text != s else { continue }
            let candidate = score(text)
            if best == nil || candidate.value > best?.score ?? 0 {
                best = (text, candidate.value, candidate.letters)
            }
        }
        guard let best else { return s }
        let gain = best.score - original.value
        let isClean = best.score >= 1 && best.letters >= minimumLettersForCleanResult
        if gain >= requiredGain || (isClean && gain >= requiredGainForCleanResult) { return best.text }
        return s
    }

    /// Share of letter-bearing words that look coherent: all letters in the string's dominant script,
    /// no non-ASCII symbols or punctuation glued to them, and no upper-case letter right after a lower-case one.
    private static func score(_ text: String) -> (value: Double, letters: Int) {
        var scriptCounts: [ScriptTraits.Script: Int] = [:]
        for character in text {
            if let script = ScriptTraits.script(of: character) { scriptCounts[script, default: 0] += 1 }
        }
        let letters = scriptCounts.values.reduce(0, +)
        guard let dominant = scriptCounts.max(by: { $0.value < $1.value })?.key else { return (1, 0) }

        var total = 0
        var coherent = 0
        for word in text.split(whereSeparator: \.isWhitespace) where word.contains(where: \.isLetter) {
            total += 1
            if isCoherent(word, dominant: dominant) { coherent += 1 }
        }
        return (total == 0 ? 1 : Double(coherent) / Double(total), letters)
    }

    /// Typographic punctuation that may open a word (`“Hello`, `«Привет`, `¿Qué`).
    private static let openingPunctuation: Set<Character> = [
        "“", "”", "„", "«", "»", "‹", "›", "‘", "‚", "—", "–", "…", "¿", "¡", "•", "§",
    ]
    /// Typographic punctuation that may close a word (`world”`, `Привет!»`, `end…`).
    private static let closingPunctuation: Set<Character> = openingPunctuation.union(["’", "®", "™", "°", "©"])
    /// Non-ASCII punctuation that may sit inside a word (`L’été`, `word—word`).
    private static let interiorPunctuation: Set<Character> = ["’", "ʼ", "—", "–", "‑", "·", "…"]
    /// Letters that signal a wrong decoding when they appear in running text (Serbian/Macedonian
    /// capitals and lower-case forms that Mac Cyrillic produces for Windows-1251 capitals).
    private static let implausibleLetters: Set<Character> = ["Ђ", "Ѓ", "Љ", "Њ", "Ћ", "Ќ", "Џ", "ђ", "ѓ", "љ", "њ", "ћ", "ќ", "џ"]

    /// A word is coherent when its letters share the dominant script, it has no implausible letters, no
    /// upper-case letter follows a lower-case one, and non-ASCII punctuation appears only where
    /// typography puts it: opening quotes before, closing quotes and dashes after, apostrophes inside.
    private static func isCoherent(_ word: Substring, dominant: ScriptTraits.Script) -> Bool {
        let characters = Array(word)
        guard let first = characters.firstIndex(where: { $0.isLetter || $0.isNumber }),
              let last = characters.lastIndex(where: { $0.isLetter || $0.isNumber }) else { return true }
        for character in characters[..<first] where !character.isASCII && !openingPunctuation.contains(character) {
            return false
        }
        for character in characters[(last + 1)...] where !character.isASCII && !closingPunctuation.contains(character) {
            return false
        }
        var previousWasLower = false
        for character in characters[first...last] {
            if let script = ScriptTraits.script(of: character) {
                if script != dominant || implausibleLetters.contains(character) { return false }
                if previousWasLower && character.isUppercase { return false }
                previousWasLower = character.isLowercase
            } else {
                previousWasLower = false
                if !character.isASCII && !character.isNumber && !interiorPunctuation.contains(character) { return false }
            }
        }
        return true
    }
}
