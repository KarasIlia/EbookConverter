import Foundation

/// Makes sloppy (HTML-style) markup acceptable to the strict `XMLParser`.
///
/// - HTML named character references become numeric ones (`&nbsp;` needs the DTD otherwise).
/// - A bare `&` that starts no valid reference becomes `&amp;`.
/// - Unclosed void elements (`<br>`) become self-closing; stray end tags of void elements are dropped.
///
/// Non-UTF-8 documents (UTF-16 by BOM or first bytes, or a legacy `encoding=` declaration) are transcoded to
/// UTF-8 first and the declaration is removed, so the byte-level rewriting below only ever sees ASCII-compatible text.
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
        let greekLower = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigmaf sigma tau upsilon phi chi psi omega"
            .split(separator: " ")
        for (offset, name) in greekLower.enumerated() { result[String(name)] = 0x3B1 + offset }
        let greekUpper = "Alpha Beta Gamma Delta Epsilon Zeta Eta Theta Iota Kappa Lambda Mu Nu Xi Omicron Pi Rho"
            .split(separator: " ")
        for (offset, name) in greekUpper.enumerated() { result[String(name)] = 0x391 + offset }
        let greekUpperTail = "Sigma Tau Upsilon Phi Chi Psi Omega".split(separator: " ")
        for (offset, name) in greekUpperTail.enumerated() { result[String(name)] = 0x3A3 + offset }
        let math: [String: Int] = [
            "thetasym": 0x3D1, "upsih": 0x3D2, "piv": 0x3D6, "oline": 0x203E, "frasl": 0x2044,
            "weierp": 0x2118, "image": 0x2111, "real": 0x211C, "alefsym": 0x2135,
            "lArr": 0x21D0, "uArr": 0x21D1, "rArr": 0x21D2, "dArr": 0x21D3, "hArr": 0x21D4, "crarr": 0x21B5,
            "forall": 0x2200, "part": 0x2202, "exist": 0x2203, "empty": 0x2205, "nabla": 0x2207,
            "isin": 0x2208, "notin": 0x2209, "ni": 0x220B, "prod": 0x220F, "sum": 0x2211, "lowast": 0x2217,
            "radic": 0x221A, "prop": 0x221D, "ang": 0x2220, "and": 0x2227, "or": 0x2228, "cap": 0x2229,
            "cup": 0x222A, "int": 0x222B, "there4": 0x2234, "sim": 0x223C, "cong": 0x2245, "asymp": 0x2248,
            "equiv": 0x2261, "sub": 0x2282, "sup": 0x2283, "nsub": 0x2284, "sube": 0x2286, "supe": 0x2287,
            "oplus": 0x2295, "otimes": 0x2297, "perp": 0x22A5, "sdot": 0x22C5,
            "lceil": 0x2308, "rceil": 0x2309, "lfloor": 0x230A, "rfloor": 0x230B,
            "lang": 0x2329, "rang": 0x232A, "loz": 0x25CA,
            "spades": 0x2660, "clubs": 0x2663, "hearts": 0x2665, "diams": 0x2666,
        ]
        return result.merging(others) { first, _ in first }.merging(math) { first, _ in first }
    }()

    private static let voidElements: Set<String> = [
        "br", "hr", "img", "meta", "link", "input", "col", "area", "base", "wbr", "source",
    ]

    /// Full clean-up: void elements first, then character references.
    static func sanitized(_ data: Data) -> Data {
        numericReferences(in: selfClosingVoidElements(in: utf8Document(from: data)))
    }

    /// `data` as UTF-8 with any `encoding=` declaration removed; unchanged if it is already UTF-8 or undecodable.
    static func utf8Document(from data: Data) -> Data {
        let bytes = [UInt8](data.prefix(4))
        var encoding: String.Encoding?
        var payload = data
        if bytes.starts(with: [0xFF, 0xFE]) {
            encoding = .utf16LittleEndian
            payload = data.dropFirst(2)
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16BigEndian
            payload = data.dropFirst(2)
        } else if bytes.starts(with: [0x3C, 0x00]) {
            encoding = .utf16LittleEndian
        } else if bytes.starts(with: [0x00, 0x3C]) {
            encoding = .utf16BigEndian
        } else if !bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            encoding = declaredEncoding(in: data)
        }
        guard let encoding, let text = String(data: payload, encoding: encoding) else { return data }
        return Data(removingEncodingDeclaration(from: text).utf8)
    }

    /// A non-UTF-8 encoding named in the XML declaration, if any.
    private static func declaredEncoding(in data: Data) -> String.Encoding? {
        let head = String(decoding: data.prefix(200), as: UTF8.self)
        guard head.hasPrefix("<?xml"),
              let match = head.firstMatch(of: /encoding\s*=\s*["']([A-Za-z0-9._:-]+)["']/) else { return nil }
        let name = String(match.1)
        let lowered = name.lowercased()
        if lowered == "utf-8" || lowered == "utf8" || lowered == "us-ascii" { return nil }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static func removingEncodingDeclaration(from text: String) -> String {
        guard text.hasPrefix("<?xml"), let end = text.range(of: "?>") else { return text }
        let declaration = text[..<end.lowerBound]
        let cleaned = declaration.replacing(/\s+encoding\s*=\s*("[^"]*"|'[^']*')/, with: "")
        return String(cleaned) + text[end.lowerBound...]
    }

    /// Returns `data` with every named reference other than the five XML ones replaced by `&#N;`
    /// (unknown names are dropped) and every bare `&` escaped.
    static func numericReferences(in data: Data) -> Data {
        guard data.contains(UInt8(ascii: "&")) else { return data }
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "&") else {
                output.append(byte)
                index += 1
                continue
            }
            guard let end = referenceEnd(in: bytes, at: index) else {
                output.append(contentsOf: Array("&amp;".utf8))
                index += 1
                continue
            }
            let body = String(decoding: bytes[index + 1..<end], as: UTF8.self)
            if body.hasPrefix("#") {
                if isValidXMLCharacterReference(body) {
                    output.append(contentsOf: bytes[index...end])
                } else {
                    output.append(contentsOf: Array("&#65533;".utf8))
                }
            } else if xmlPredefined.contains(body) {
                output.append(contentsOf: bytes[index...end])
            } else if let code = table[body] {
                output.append(contentsOf: Array("&#\(code);".utf8))
            }
            index = end + 1
        }
        return Data(output)
    }

    /// Whether `#123` / `#x7B` names a character allowed in XML 1.0.
    private static func isValidXMLCharacterReference(_ body: String) -> Bool {
        let digits = body.dropFirst()
        let value = digits.first == "x" || digits.first == "X"
            ? Int(digits.dropFirst(), radix: 16) : Int(digits, radix: 10)
        guard let value else { return false }
        switch value {
        case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
        default: return false
        }
    }

    /// Index of the `;` ending a well-formed reference that starts with the `&` at `start`, or `nil`.
    private static func referenceEnd(in bytes: [UInt8], at start: Int) -> Int? {
        var end = start + 1
        guard end < bytes.count else { return nil }
        let isNumeric = bytes[end] == UInt8(ascii: "#")
        if isNumeric {
            end += 1
            let isHex = end < bytes.count && (bytes[end] == UInt8(ascii: "x") || bytes[end] == UInt8(ascii: "X"))
            if isHex { end += 1 }
            let digitsStart = end
            while end < bytes.count, end - start <= 12, isHex ? isHexDigit(bytes[end]) : isDigit(bytes[end]) { end += 1 }
            guard end > digitsStart, end < bytes.count, bytes[end] == UInt8(ascii: ";") else { return nil }
            return end
        }
        guard isNameStart(bytes[end]) else { return nil }
        while end < bytes.count, end - start <= 32, isNameCharacter(bytes[end]) { end += 1 }
        guard end < bytes.count, bytes[end] == UInt8(ascii: ";") else { return nil }
        return end
    }

    /// Rewrites `<br>` as `<br/>` and drops `</br>`, leaving comments, CDATA and declarations alone.
    static func selfClosingVoidElements(in data: Data) -> Data {
        let lt = UInt8(ascii: "<")
        guard data.contains(lt) else { return data }
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + 16)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == lt else {
                output.append(bytes[index])
                index += 1
                continue
            }
            if let skipped = skipMarkup(in: bytes, at: index) {
                output.append(contentsOf: bytes[index..<skipped])
                index = skipped
                continue
            }
            let isClosing = index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/")
            var nameEnd = index + (isClosing ? 2 : 1)
            let nameStart = nameEnd
            while nameEnd < bytes.count, isNameCharacter(bytes[nameEnd]) || bytes[nameEnd] == UInt8(ascii: "-") { nameEnd += 1 }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self).lowercased()
            guard voidElements.contains(name), let close = tagEnd(in: bytes, from: nameEnd) else {
                output.append(bytes[index])
                index += 1
                continue
            }
            if isClosing {
                // `</br>` has no place in XML.
            } else if bytes[close - 1] == UInt8(ascii: "/") {
                output.append(contentsOf: bytes[index...close])
            } else {
                output.append(contentsOf: bytes[index..<close])
                output.append(contentsOf: Array("/>".utf8))
            }
            index = close + 1
        }
        return Data(output)
    }

    /// End (exclusive) of a comment, CDATA section, processing instruction or declaration starting at `start`.
    private static func skipMarkup(in bytes: [UInt8], at start: Int) -> Int? {
        func hasPrefix(_ text: String) -> Bool {
            let pattern = Array(text.utf8)
            return start + pattern.count <= bytes.count && Array(bytes[start..<start + pattern.count]) == pattern
        }
        func find(_ text: String) -> Int {
            let pattern = Array(text.utf8)
            var i = start
            while i + pattern.count <= bytes.count {
                if Array(bytes[i..<i + pattern.count]) == pattern { return i + pattern.count }
                i += 1
            }
            return bytes.count
        }
        if hasPrefix("<!--") { return find("-->") }
        if hasPrefix("<![CDATA[") { return find("]]>") }
        if hasPrefix("<?") { return find("?>") }
        if hasPrefix("<!") { return find(">") }
        return nil
    }

    /// Index of the `>` closing the tag whose name ended at `from`, skipping quoted attribute values.
    private static func tagEnd(in bytes: [UInt8], from: Int) -> Int? {
        var index = from
        var quote: UInt8?
        while index < bytes.count {
            let byte = bytes[index]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: ">") {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
    }

    private static func isNameStart(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isNameCharacter(_ byte: UInt8) -> Bool {
        isNameStart(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
