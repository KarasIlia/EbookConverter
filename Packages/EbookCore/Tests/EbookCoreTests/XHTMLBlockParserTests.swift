import Foundation
import Testing
@testable import EbookCore

@Suite struct XHTMLBlockParserTests {
    private func parse(_ body: String, resolve: (String) -> ImageAsset? = { _ in nil }) -> XHTMLBlockParser.Content {
        let xhtml = "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>ignored</title></head><body>\(body)</body></html>"
        return XHTMLBlockParser.parse(Data(xhtml.utf8), resolveImage: resolve)
    }

    @Test func inlineStylesBreaksAndWhitespace() {
        let content = parse("<p>  Hello <b>bold <i>both</i></b>\n  <em>it</em><br/>next   line </p>")
        #expect(content.blocks == [.paragraph([
            InlineRun("Hello "), InlineRun("bold ", bold: true), InlineRun("both", bold: true, italic: true),
            InlineRun(" "), InlineRun("it", italic: true), InlineRun(" next line"),
        ])])
    }

    @Test func firstLeadingHeadingIsTheTitleOthersAreBlocks() {
        let content = parse("<h2>Chapter <i>One</i></h2><p>Body.</p><h1>Late</h1><h4>Sub</h4>")
        #expect(content.title == [InlineRun("Chapter "), InlineRun("One", italic: true)])
        #expect(content.blocks == [
            .paragraph([InlineRun("Body.")]),
            .heading(level: 1, runs: [InlineRun("Late")]),
            .heading(level: 3, runs: [InlineRun("Sub")]),
        ])
    }

    @Test func blocksFromDropsTitleAndHandlesEntitiesAndStrayText() {
        let xhtml = "<html><body><h1>T</h1><div>Loose <span>text</span><p>Para&nbsp;one &mdash; &amp; &unknown;done</p>tail</div></body></html>"
        let blocks = XHTMLBlockParser.blocks(from: Data(xhtml.utf8), resolveImage: { _ in nil })
        #expect(blocks == [
            .paragraph([InlineRun("Loose text")]),
            .paragraph([InlineRun("Para\u{A0}one \u{2014} & done")]),
            .paragraph([InlineRun("tail")]),
        ])
    }

    @Test func imagesResolveFromImgAndSvgImage() {
        var requested: [String] = []
        let asset = FixtureFactory.pngImage(width: 1, height: 1)
        let content = parse("""
        <p>A</p><img src="a.png"/><svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="b.png"/></svg><img src="gone.png"/>
        """) { source in
            requested.append(source)
            return source == "gone.png" ? nil : asset
        }
        #expect(requested == ["a.png", "b.png", "gone.png"])
        #expect(content.blocks == [.paragraph([InlineRun("A")]), .image(asset), .image(asset)])
    }

    @Test func malformedMarkupKeepsTextParsedSoFar() {
        let content = parse("<p>Kept.</p><p>Broken <b></p>")
        #expect(content.blocks.first == .paragraph([InlineRun("Kept.")]))
    }

    @Test func bareAmpersandKeepsAllContent() {
        let content = parse("<p>AT&T and Q&A &#233; &#xE9; &alpha;&Omega; &amp; end</p><p>after</p>")
        #expect(content.blocks == [
            .paragraph([InlineRun("AT&T and Q&A \u{E9} \u{E9} \u{3B1}\u{3A9} & end")]),
            .paragraph([InlineRun("after")]),
        ])
        #expect(!content.isTruncated)
    }

    @Test func unclosedVoidElementsDoNotTruncate() {
        let content = parse("<p>a<br>b<BR></br></p><hr><p>after<img src=\"x.png\"></p>")
        #expect(content.blocks == [.paragraph([InlineRun("a b")]), .paragraph([InlineRun("after")])])
        #expect(!content.isTruncated)
    }

    @Test func parseErrorsAreReported() {
        #expect(parse("<p>Kept.</p><p>Broken <b></p>").isTruncated)
    }
}
