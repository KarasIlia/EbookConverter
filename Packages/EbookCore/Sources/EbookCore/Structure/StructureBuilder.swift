import Foundation

/// Detects headings in an importer's flat paragraph stream and builds the chapter hierarchy.
///
/// Signals are language-independent: explicit markup hints, multilingual `HeadingPatterns`,
/// font size relative to the body text, and bold-only short lines.
public enum StructureBuilder {
    /// Longest paragraph (in characters) that can still be a heading.
    static let maxHeadingLength = 120
    /// A paragraph this many times larger than the body font size is a heading candidate.
    static let headingSizeRatio = 1.15
    /// Level of in-chapter subheadings.
    static let subheadingLevel = 3
    /// Endings that disqualify non-pattern candidates (they read as sentences or lead-ins).
    private static let terminalPunctuation: Set<Character> = [".", ",", ";", ":"]

    /// How a single paragraph may act as a heading.
    private enum Candidate {
        /// Tier fixed by markup hint or textual pattern.
        case fixed(tier: Int, fontSize: Double?)
        /// Tier decided by ranking of distinct font sizes.
        case sized(Double)
        /// Bold-only line at body size.
        case bold
        case none
    }

    public static func build(_ items: [StructuredItem]) -> (chapters: [Chapter], foundHeadings: Bool) {
        let items = items.filter { item in
            if case .paragraph(let paragraph) = item { !trimmedText(paragraph).isEmpty } else { true }
        }
        let bodySize = bodyFontSize(of: items)
        let candidates = items.map { candidate(for: $0, bodySize: bodySize) }
        let tiers = assignTiers(candidates)
        let presentTiers = Set(tiers.compactMap(\.self))

        guard let topTier = presentTiers.min() else {
            let blocks = items.map(block(for:))
            return (blocks.isEmpty ? [] : [Chapter(blocks: blocks)], false)
        }
        let partTier: Int? = presentTiers.contains(1) && presentTiers.contains(2) ? 1 : nil
        let chapterTier = partTier == nil ? topTier : 2
        return (assemble(items, tiers: tiers, partTier: partTier, chapterTier: chapterTier), true)
    }

    // MARK: - Classification

    private static func trimmedText(_ paragraph: StyledParagraph) -> String {
        paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Font sizes are grouped at 0.1 pt so PDF rounding noise does not create extra tiers.
    private static func normalized(_ size: Double) -> Double {
        (size * 10).rounded() / 10
    }

    /// The size carrying the most characters; ties go to the smaller size.
    private static func bodyFontSize(of items: [StructuredItem]) -> Double? {
        var characters: [Double: Int] = [:]
        for case .paragraph(let paragraph) in items {
            guard let size = paragraph.fontSize else { continue }
            characters[normalized(size), default: 0] += paragraph.text.count
        }
        return characters.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key
    }

    private static func candidate(for item: StructuredItem, bodySize: Double?) -> Candidate {
        guard case .paragraph(let paragraph) = item else { return .none }
        let text = trimmedText(paragraph)
        guard text.count <= maxHeadingLength else { return .none }
        let size = paragraph.fontSize.map(normalized)
        let hint = paragraph.headingLevelHint.map { max(1, $0) }
        let isLarger = if let size, let bodySize { size >= bodySize * headingSizeRatio } else { false }

        // Weak pattern matches ("Книга упала.") need a second signal to count as headings.
        if let pattern = HeadingPatterns.match(text),
           !pattern.needsSupport || hint != nil || isLarger || paragraph.isAllBold {
            return .fixed(tier: hint ?? (pattern.kind == .part ? 1 : 2), fontSize: size)
        }
        // Explicit markup is authoritative: "## Note:" is a heading despite the colon.
        if let hint { return .fixed(tier: hint, fontSize: size) }
        if let last = text.last, terminalPunctuation.contains(last) { return .none }
        if let size, isLarger { return .sized(size) }
        if paragraph.isAllBold { return .bold }
        return .none
    }

    /// Resolves every candidate to a tier (1 = top), or `nil` for body content.
    private static func assignTiers(_ candidates: [Candidate]) -> [Int?] {
        var fixed: [(tier: Int, fontSize: Double?)] = []
        var sizes = Set<Double>()
        for candidate in candidates {
            switch candidate {
            case .fixed(let tier, let fontSize): fixed.append((tier, fontSize))
            case .sized(let size): sizes.insert(size)
            case .bold, .none: break
            }
        }

        // Largest size takes the next free tier; a size shared with fixed headings joins their tier,
        // and a size smaller than a fixed heading ranks below it.
        var occupied = Set(fixed.map(\.tier))
        var sizeTiers: [Double: Int] = [:]
        var lastTier = 0
        for size in sizes.sorted(by: >) {
            if let shared = fixed.filter({ $0.fontSize == size }).map(\.tier).min() {
                sizeTiers[size] = shared
                lastTier = max(lastTier, shared)
                continue
            }
            let largerFixedTier = fixed.filter { ($0.fontSize ?? 0) > size }.map(\.tier).max() ?? 0
            var tier = max(lastTier, largerFixedTier) + 1
            while occupied.contains(tier) { tier += 1 }
            sizeTiers[size] = tier
            occupied.insert(tier)
            lastTier = tier
        }

        var tiers: [Int?] = candidates.map { candidate in
            switch candidate {
            case .fixed(let tier, _): tier
            case .sized(let size): sizeTiers[size]
            case .bold, .none: nil
            }
        }
        // Bold body-size lines are subheadings under real chapters, otherwise they split chapters.
        let hasChapterTier = tiers.contains { $0 == 1 || $0 == 2 }
        let boldTier = hasChapterTier ? subheadingLevel : 2
        for (index, candidate) in candidates.enumerated() {
            if case .bold = candidate { tiers[index] = boldTier }
        }
        return tiers
    }

    // MARK: - Assembly

    private static func block(for item: StructuredItem) -> Block {
        switch item {
        case .paragraph(let paragraph): .paragraph(paragraph.runs)
        case .image(let asset): .image(asset)
        }
    }

    private static func assemble(_ items: [StructuredItem], tiers: [Int?], partTier: Int?, chapterTier: Int) -> [Chapter] {
        var chapters: [Chapter] = []
        var leading: [Block] = []
        var part: Chapter?
        var chapter: Chapter?

        func closeChapter() {
            guard let finished = chapter else { return }
            if var openPart = part {
                openPart.children.append(finished)
                part = openPart
            } else {
                chapters.append(finished)
            }
            chapter = nil
        }

        func closePart() {
            closeChapter()
            if let finished = part { chapters.append(finished) }
            part = nil
        }

        func append(_ block: Block) {
            if chapter != nil {
                chapter?.blocks.append(block)
            } else if part != nil {
                part?.blocks.append(block)
            } else {
                leading.append(block)
            }
        }

        for (item, tier) in zip(items, tiers) {
            guard let tier, case .paragraph(let paragraph) = item else {
                append(block(for: item))
                continue
            }
            if tier == partTier {
                closePart()
                part = Chapter(title: trimmedText(paragraph))
            } else if tier == chapterTier {
                closeChapter()
                chapter = Chapter(title: trimmedText(paragraph))
            } else {
                append(.heading(level: subheadingLevel, runs: paragraph.runs))
            }
        }
        closePart()

        if !leading.isEmpty {
            chapters.insert(Chapter(blocks: leading), at: 0)
        }
        return chapters
    }
}
