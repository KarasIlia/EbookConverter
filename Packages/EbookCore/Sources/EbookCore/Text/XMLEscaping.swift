/// Escaping of text for inclusion in XML 1.0 documents.
public enum XMLEscaping {
    /// Escapes `& < > " '` and drops characters that are not allowed in XML 1.0
    /// (U+0000–U+0008, U+000B, U+000C, U+000E–U+001F, U+FFFE, U+FFFF).
    public static func escape(_ s: String) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(s.unicodeScalars.count)
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0xFFFE, 0xFFFF:
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
