import AppKit

/// Turns an `NSAttributedString` (from RTF, DOC, DOCX or HTML) into paragraphs with style signals and images.
public enum AttributedStringFlattener {
    private static let attachmentCharacter: Character = "\u{FFFC}"
    /// Deepest heading level kept from `NSParagraphStyle.headerLevel` (matches Markdown's `###`).
    private static let deepestHeadingLevel = 3

    /// Paragraphs and images in document order. Image ids are `img-<n>` in order of the attachments kept.
    public static func items(from string: NSAttributedString) -> [StructuredItem] {
        var imageCount = 0
        return items(from: string) { _, attachment in
            guard let attachment, let asset = imageAsset(of: attachment, id: "img-\(imageCount + 1)") else { return nil }
            imageCount += 1
            return asset
        }
    }

    /// Like `items(from:)`, but asks `image` for each U+FFFC position (0-based, document order) together with
    /// its attachment, if any. Returning `nil` drops the position.
    static func items(
        from string: NSAttributedString,
        image: (_ index: Int, _ attachment: NSTextAttachment?) -> ImageAsset?
    ) -> [StructuredItem] {
        let string = normalizingBreakControls(string)
        let text = string.string as NSString
        var items: [StructuredItem] = []
        var attachmentIndex = 0

        var paragraphRanges: [NSRange] = []
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]
        ) { _, range, _, _ in
            paragraphRanges.append(range)
        }

        for paragraphRange in paragraphRanges {
            var runs: [InlineRun] = []
            var characterCounts: [Double: Int] = [:]
            let headerLevel = paragraphRange.length > 0
                ? (string.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0
                : 0

            func flush() {
                defer {
                    runs = []
                    characterCounts = [:]
                }
                guard runs.contains(where: { !$0.text.allSatisfy(\.isWhitespace) }) else { return }
                let fontSize = characterCounts.max { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
                }?.key
                let hint = headerLevel > 0 ? min(headerLevel, deepestHeadingLevel) : nil
                items.append(.paragraph(StyledParagraph(runs: runs, fontSize: fontSize, headingLevelHint: hint)))
            }

            string.enumerateAttributes(in: paragraphRange) { attributes, range, _ in
                let piece = text.substring(with: range)
                var segments = piece.split(separator: attachmentCharacter, omittingEmptySubsequences: false)
                let first = segments.removeFirst()
                append(String(first), attributes: attributes, to: &runs, counts: &characterCounts)
                for segment in segments {
                    if let asset = image(attachmentIndex, attributes[.attachment] as? NSTextAttachment) {
                        flush()
                        items.append(.image(asset))
                    }
                    attachmentIndex += 1
                    append(String(segment), attributes: attributes, to: &runs, counts: &characterCounts)
                }
            }
            flush()
        }
        return items
    }

    /// Word processors separate words with U+000B (manual line break) and U+2028, and pages with U+000C;
    /// XML drops the controls, which would glue words. Line breaks become a word separator, form feeds paragraph breaks.
    private static func normalizingBreakControls(_ string: NSAttributedString) -> NSAttributedString {
        let source = string.string as NSString
        let controls = CharacterSet(charactersIn: "\u{0B}\u{0C}\u{2028}")
        guard source.rangeOfCharacter(from: controls).location != NSNotFound else { return string }
        let result = NSMutableAttributedString(attributedString: string)
        let text = result.mutableString
        func character(at index: Int) -> Character? {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return nil }
            return Character(scalar)
        }
        // Back to front, so replacements do not shift the positions still to visit.
        var index = text.length - 1
        while index >= 0 {
            let unit = text.character(at: index)
            if unit == 0x0C {
                text.replaceCharacters(in: NSRange(location: index, length: 1), with: "\n")
            } else if unit == 0x0B || unit == 0x2028 {
                let separator = LineJoiner.separator(between: character(at: index - 1), and: character(at: index + 1))
                text.replaceCharacters(in: NSRange(location: index, length: 1), with: separator)
            }
            index -= 1
        }
        return result
    }

    private static func append(
        _ piece: String, attributes: [NSAttributedString.Key: Any],
        to runs: inout [InlineRun], counts: inout [Double: Int]
    ) {
        guard !piece.isEmpty else { return }
        let font = attributes[.font] as? NSFont
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        if let font {
            counts[Double(font.pointSize), default: 0] += piece.count
        }
        let run = InlineRun(piece, bold: traits.contains(.bold), italic: traits.contains(.italic))
        if var last = runs.last, last.isBold == run.isBold, last.isItalic == run.isItalic {
            last.text += run.text
            runs[runs.count - 1] = last
        } else {
            runs.append(run)
        }
    }

    /// The attachment's image (file contents, else a TIFF rendering of its `image`), normalized.
    static func imageAsset(of attachment: NSTextAttachment, id: String) -> ImageAsset? {
        let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents ?? attachment.image?.tiffRepresentation
        return data.flatMap { ImageNormalizer.normalize($0, id: id) }
    }
}
