/// A block-level element of a chapter.
public enum Block: Sendable, Hashable {
    case heading(level: Int, runs: [InlineRun])
    case paragraph([InlineRun])
    case image(ImageAsset)
}
