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
        case .paragraph(let runs):
            Text(Self.attributedText(runs))
                .textSelection(.enabled)
        case .image(let asset):
            if let image = imageCache.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // Never upscale beyond the image's own size; the column width caps it otherwise.
                    .frame(maxWidth: CGFloat(asset.pixelWidth))
                    .frame(maxWidth: .infinity)
            }
        }
    }

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
