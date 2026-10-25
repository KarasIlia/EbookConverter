/// A lexical unit of RTF source.
enum RTFToken: Equatable {
    case groupStart
    case groupEnd
    /// `\name` with optional signed numeric parameter, e.g. `\fcharset204`, `\ansicpg`.
    case controlWord(String, Int?)
    /// `\` followed by a non-letter other than `'`, `\`, `{`, `}` (e.g. `\*`, `\~`).
    case controlSymbol(UInt8)
    /// A text byte: raw, from `\'hh`, or an escaped `\\`, `\{`, `\}`.
    case byte(UInt8)
}
