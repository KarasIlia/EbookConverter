import Foundation

/// Loads images referenced by relative path from a source document.
public enum HTMLImageResolver {
    /// - Parameters:
    ///   - reference: the raw `src` / link destination, possibly percent-encoded.
    ///   - fileURL: the source document; relative references resolve against its folder.
    ///   - accessibleFolder: folder the user granted access to; nil if none was granted.
    ///   - id: identifier given to the resulting asset.
    public static func loadLocalImage(
        reference: String,
        relativeTo fileURL: URL,
        accessibleFolder: URL?,
        id: String
    ) -> ImageLoadOutcome {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        // `//host/path` is protocol-relative: a network reference, not a local path.
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("//") { return .remote }
        // Other schemes (data:, mailto:) are neither local files nor fetchable.
        if let scheme = URL(string: trimmed)?.scheme, scheme.lowercased() != "file" { return .missing }

        let path: String
        if let url = URL(string: trimmed), url.isFileURL {
            path = url.path(percentEncoded: false)
        } else {
            // Drop any query/fragment, then percent-decode; a literal (unencoded) name decodes to itself.
            let bare = trimmed.prefix { $0 != "?" && $0 != "#" }
            path = String(bare).removingPercentEncoding ?? String(bare)
        }
        guard !path.isEmpty else { return .missing }
        let folder = fileURL.deletingLastPathComponent()
        let target = path.hasPrefix("/")
            ? URL(filePath: path)
            : folder.appending(path: path).standardizedFileURL

        let scoped = accessibleFolder?.startAccessingSecurityScopedResource() == true
        defer { if scoped { accessibleFolder?.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: target) else {
            return accessibleFolder == nil ? .needsFolderAccess(target) : .missing
        }
        guard let asset = ImageNormalizer.normalize(data, id: id) else { return .missing }
        return .loaded(asset)
    }

    /// The folder to ask access for: the document's folder, or its nearest ancestor that also contains
    /// every unreadable image in `targets` (`../pics/a.png` → the parent of the document's folder).
    public static func folderCovering(_ targets: [URL], relativeTo fileURL: URL) -> URL {
        var folder = fileURL.deletingLastPathComponent()
        let targetComponents = targets.map(\.standardizedFileURL.pathComponents)
        while true {
            let components = folder.standardizedFileURL.pathComponents
            if components.count <= 1 || targetComponents.allSatisfy({ $0.starts(with: components) }) {
                return folder
            }
            folder = folder.standardizedFileURL.deletingLastPathComponent()
        }
    }
}
