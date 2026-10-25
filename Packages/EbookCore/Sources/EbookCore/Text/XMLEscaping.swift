/// Escaping of text for inclusion in XML 1.0 documents.
public enum XMLEscaping {
    /// Escapes `& < > " '` and drops characters that are not allowed in XML 1.0
    /// (U+0000–U+0008, U+000E–U+001F, U+FFFE, U+FFFF).
    ///
    /// Line-break controls that separate words in word processors (U+000B vertical tab, U+000C form feed,
    /// U+2028 line separator) become a space, or nothing between two characters of scripts written without spaces.
    public static func escape(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var result = String.UnicodeScalarView()
        result.reserveCapacity(scalars.count)
        for (index, scalar) in scalars.enumerated() {
            switch scalar.value {
            case 0x0B, 0x0C, 0x2028:
                let previous = index > 0 ? Character(scalars[index - 1]) : nil
                let next = index + 1 < scalars.count ? Character(scalars[index + 1]) : nil
                result.append(contentsOf: LineJoiner.separator(between: previous, and: next).unicodeScalars)
            case 0x00...0x08, 0x0E...0x1F, 0xFFFE, 0xFFFF:
                continue
            case 0x26: result.append(contentsOf: "&amp;".unicodeScalars)
            case 0x3C: result.append(contentsOf: "&lt;".unicodeScalars)
            case 0x3E: result.append(contentsOf: "&gt;".unicodeScalars)
            case 0x22: result.append(contentsOf: "&quot;".unicodeScalars)
            case 0x27: result.append(contentsOf: "&apos;".unicodeScalars)
            default: result.append(scalar)
            }
        }
        return String(result)
    }
}
