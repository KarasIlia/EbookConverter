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

    private static func isCoherent(_ word: Substring, dominant: ScriptTraits.Script) -> Bool {
        var previousWasLower = false
        for character in word {
            if let script = ScriptTraits.script(of: character) {
                if script != dominant { return false }
                if previousWasLower && character.isUppercase { return false }
                previousWasLower = character.isLowercase
            } else {
                previousWasLower = false
                if !character.isASCII && !character.isNumber { return false }
            }
        }
        return true
    }
}
