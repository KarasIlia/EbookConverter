import Foundation

extension String {
    /// Shortens the string to at most `maxLength` characters by replacing its middle with "…",
    /// keeping the start and the end (e.g. the file extension) readable. Counts grapheme clusters, so any script is safe.
    func middleTruncated(maxLength: Int) -> String {
        guard count > maxLength, maxLength > 1 else { return self }
        let tailLength = (maxLength - 1) / 2
        let headLength = maxLength - 1 - tailLength
        return String(prefix(headLength)) + "…" + String(suffix(tailLength))
    }
}
