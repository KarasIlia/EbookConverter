import SwiftUI
import EbookCore

/// One block of a chapter in the preview: a heading, a paragraph or an image.
struct BlockView: View {
    let block: Block
    let imageCache: PreviewImageCache

    var body: some View {
        switch block {
        case .heading(let level, let runs):
            Text(Self.attributedText(runs))
                .font(Self.headingFont(level: level))
                .bold()
                .padding(.vertical)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let runs):
            // Like the exported book (`text-indent: 1.5em`, no gap between paragraphs): a first-line indent marks
            // each paragraph. SwiftUI Text has no first-line indent, so an em space + en space (1.5 em) leads the text.
            Text(AttributedString(Self.firstLineIndent) + Self.attributedText(runs))
                .textSelection(.enabled)
        case .image(let asset):
            if let image = imageCache.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Never upscale beyond the image's own size; the column width caps it otherwise.
                    .frame(maxWidth: CGFloat(asset.pixelWidth))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .accessibilityLabel(Text(.previewImage))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(.previewImage))
            }
        }
    }

    /// Em space + en space: the 1.5 em first-line indent of exported paragraphs.
    static let firstLineIndent = "\u{2003}\u{2002}"

    static func headingFont(level: Int) -> Font {
        switch level {
        case ...1: .title
        case 2: .title2
        default: .title3
        }
    }

    /// Runs joined into one string, bold/italic expressed as presentation intents so the
    /// surrounding font (serif body or heading) is kept.
    static func attributedText(_ runs: [InlineRun]) -> AttributedString {
        runs.reduce(into: AttributedString()) { text, run in
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.isBold { intent.insert(.stronglyEmphasized) }
            if run.isItalic { intent.insert(.emphasized) }
            if !intent.isEmpty {
                piece.inlinePresentationIntent = intent
            }
            text.append(piece)
        }
    }
}
