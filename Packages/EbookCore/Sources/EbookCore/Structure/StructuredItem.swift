/// An importer's flat output, before chapters are detected.
public enum StructuredItem: Sendable, Hashable {
    case paragraph(StyledParagraph)
    case image(ImageAsset)
}
