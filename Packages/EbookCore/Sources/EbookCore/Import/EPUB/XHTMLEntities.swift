import Foundation

/// Rewrites HTML named character references as numeric ones.
///
/// EPUB XHTML often uses `&nbsp;` and friends, which a non-validating `XMLParser` rejects without the DTD.
/// Works on raw bytes (the references are ASCII), so the document's declared encoding is untouched.
enum XHTMLEntities {
    private static let xmlPredefined: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    private static let table: [String: Int] = {
        // ISO 8859-1 block, U+00A0...U+00FF in order.
        let latin1 = """
        nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn sup2 sup3 \
        acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde \
        Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute \
        Ocirc Otilde Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde \
        auml aring aelig ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute \
        ocirc otilde ouml divide oslash ugrave uacute ucirc uuml yacute thorn yuml
        """.split(separator: " ")
        var result: [String: Int] = [:]
        for (offset, name) in latin1.enumerated() { result[String(name)] = 0xA0 + offset }
        let others: [String: Int] = [
            "ensp": 0x2002, "emsp": 0x2003, "thinsp": 0x2009, "zwnj": 0x200C, "zwj": 0x200D,
            "lrm": 0x200E, "rlm": 0x200F, "ndash": 0x2013, "mdash": 0x2014,
            "lsquo": 0x2018, "rsquo": 0x2019, "sbquo": 0x201A, "ldquo": 0x201C, "rdquo": 0x201D, "bdquo": 0x201E,
            "dagger": 0x2020, "Dagger": 0x2021, "bull": 0x2022, "hellip": 0x2026, "permil": 0x2030,
            "prime": 0x2032, "Prime": 0x2033, "lsaquo": 0x2039, "rsaquo": 0x203A, "euro": 0x20AC, "trade": 0x2122,
            "larr": 0x2190, "uarr": 0x2191, "rarr": 0x2192, "darr": 0x2193, "harr": 0x2194,
            "minus": 0x2212, "infin": 0x221E, "ne": 0x2260, "le": 0x2264, "ge": 0x2265,
            "OElig": 0x152, "oelig": 0x153, "Scaron": 0x160, "scaron": 0x161, "Yuml": 0x178, "fnof": 0x192,
            "circ": 0x2C6, "tilde": 0x2DC,
        ]
        return result.merging(others) { first, _ in first }
    }()

    /// Returns `data` with every named reference other than the five XML ones replaced by `&#N;`
    /// (unknown names are dropped).
    static func numericReferences(in data: Data) -> Data {
        guard data.contains(UInt8(ascii: "&")) else { return data }
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "&"), index + 1 < bytes.count, isNameStart(bytes[index + 1]) else {
                output.append(byte)
                index += 1
                continue
            }
            var end = index + 1
            while end < bytes.count, end - index <= 32, isNameCharacter(bytes[end]) { end += 1 }
            guard end < bytes.count, bytes[end] == UInt8(ascii: ";") else {
                output.append(byte)
                index += 1
                continue
            }
            let name = String(decoding: bytes[index + 1..<end], as: UTF8.self)
            if xmlPredefined.contains(name) {
                output.append(contentsOf: bytes[index...end])
            } else if let code = table[name] {
                output.append(contentsOf: Array("&#\(code);".utf8))
            }
            index = end + 1
        }
        return Data(output)
    }

    private static func isNameStart(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isNameCharacter(_ byte: UInt8) -> Bool {
        isNameStart(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
