import Foundation

/// Path arithmetic inside a ZIP archive. Results never leave the archive root.
enum ArchivePath {
    /// Resolves `reference` (an href/src, possibly percent-encoded, with optional query/fragment)
    /// against the folder of `base`. Returns `nil` for empty references, URLs with a scheme,
    /// and paths that climb above the archive root.
    static func resolve(_ reference: String, relativeTo base: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bare = withoutFragment(trimmed), !bare.isEmpty else { return nil }
        let lowered = bare.lowercased()
        let firstSegment = lowered.prefix(while: { $0 != "/" })
        if lowered.hasPrefix("//") || firstSegment.contains(":") { return nil }
        let decoded = bare.removingPercentEncoding ?? bare

        var parts: [Substring] = decoded.hasPrefix("/") ? [] : Array(base.split(separator: "/").dropLast())
        for part in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(part)
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "/")
    }

    /// The reference without `#fragment` and `?query`; `nil` if nothing remains.
    static func withoutFragment(_ reference: String) -> String? {
        let bare = reference.prefix { $0 != "#" && $0 != "?" }
        return bare.isEmpty ? nil : String(bare)
    }
}
