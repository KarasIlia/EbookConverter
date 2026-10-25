/// Splits RTF bytes into tokens. Raw CR/LF are dropped, as RTF requires.
struct RTFLexer {
    private let bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func next() -> RTFToken? {
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "{"): return .groupStart
            case UInt8(ascii: "}"): return .groupEnd
            case UInt8(ascii: "\r"), UInt8(ascii: "\n"): continue
            case UInt8(ascii: "\\"): return control()
            default: return .byte(byte)
            }
        }
        return nil
    }

    private mutating func control() -> RTFToken? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        index += 1
        switch first {
        case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"):
            return .byte(first)
        case UInt8(ascii: "'"):
            guard index + 2 <= bytes.count,
                  let value = UInt8(String(decoding: bytes[index..<index + 2], as: UTF8.self), radix: 16) else {
                return .controlSymbol(first)
            }
            index += 2
            return .byte(value)
        case _ where Self.isLetter(first):
            var name = [first]
            while index < bytes.count, Self.isLetter(bytes[index]) {
                name.append(bytes[index])
                index += 1
            }
            var digits: [UInt8] = []
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") {
                digits.append(bytes[index])
                index += 1
            }
            while index < bytes.count, Self.isDigit(bytes[index]) {
                digits.append(bytes[index])
                index += 1
            }
            // A single space delimits the control word and is not text.
            if index < bytes.count, bytes[index] == UInt8(ascii: " ") { index += 1 }
            return .controlWord(String(decoding: name, as: UTF8.self), Int(String(decoding: digits, as: UTF8.self)))
        default:
            return .controlSymbol(first)
        }
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
