/// Removes chapters that carry nothing: no title, no content and no sub-chapters (after their own pruning).
/// Titled empty chapters stay, so an author or dedication page survives a round trip.
enum EmptyChapterPruner {
    static func pruned(_ chapters: [Chapter]) -> [Chapter] {
        chapters.compactMap { chapter in
            var chapter = chapter
            chapter.children = pruned(chapter.children)
            let isEmpty = TableOfContentsLabel.heading(of: chapter) == nil && chapter.blocks.isEmpty && chapter.children.isEmpty
            return isEmpty ? nil : chapter
        }
    }
}
