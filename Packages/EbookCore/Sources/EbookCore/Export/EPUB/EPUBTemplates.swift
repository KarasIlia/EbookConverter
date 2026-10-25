import Foundation

/// Static text templates for the files of an EPUB package.
enum EPUBTemplates {
    static let xmlDeclaration = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

    static let containerXML = xmlDeclaration + """
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>

    """

    static let stylesheet = """
    p { text-indent: 1.5em; margin: 0; }
    h1, h2, h3, h4, h5, h6 { text-align: center; }
    img { max-width: 100%; }
    div.image, div.cover { text-align: center; text-indent: 0; }

    """

    /// A complete XHTML document. `body` is already-serialized markup.
    static func xhtml(title: String, language: String, isRightToLeft: Bool, stylesheetHref: String = "../style.css", body: String) -> String {
        let lang = XMLEscaping.escape(language)
        let dir = isRightToLeft ? " dir=\"rtl\"" : ""
        return xmlDeclaration + """
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(lang)" lang="\(lang)"\(dir)>
        <head>
        <meta charset="utf-8"/>
        <title>\(XMLEscaping.escape(title))</title>
        <link rel="stylesheet" type="text/css" href="\(stylesheetHref)"/>
        </head>
        <body>
        \(body)
        </body>
        </html>

        """
    }

    static func coverBody(imagePath: String) -> String {
        "<div class=\"cover\"><img src=\"\(imagePath)\" alt=\"\"/></div>"
    }

    static func opf(
        identifier: String,
        metadata: BookMetadata,
        modified: String,
        manifest: [String],
        spine: [String],
        isRightToLeft: Bool,
        hasCover: Bool
    ) -> String {
        let direction = isRightToLeft ? " page-progression-direction=\"rtl\"" : ""
        let creator = metadata.author.isEmpty
            ? ""
            : "\n    <dc:creator>\(XMLEscaping.escape(metadata.author))</dc:creator>"
        let guide = hasCover
            ? "\n  <guide>\n    <reference type=\"cover\" title=\"Cover\" href=\"text/cover.xhtml\"/>\n  </guide>"
            : ""
        let coverMeta = hasCover ? "\n    <meta name=\"cover\" content=\"cover-image\"/>" : ""
        return xmlDeclaration + """
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="\(XMLEscaping.escape(metadata.language))">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(identifier)</dc:identifier>
            <dc:title>\(XMLEscaping.escape(metadata.title))</dc:title>\(creator)
            <dc:language>\(XMLEscaping.escape(metadata.language))</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>\(coverMeta)
          </metadata>
          <manifest>
        \(manifest.map { "    " + $0 }.joined(separator: "\n"))
          </manifest>
          <spine toc="ncx"\(direction)>
        \(spine.map { "    " + $0 }.joined(separator: "\n"))
          </spine>\(guide)
        </package>

        """
    }

    static func nav(language: String, isRightToLeft: Bool, title: String, list: String) -> String {
        let body = """
        <nav epub:type="toc" id="toc">
        <h1>\(XMLEscaping.escape(title))</h1>
        \(list)
        </nav>
        """
        return xhtml(title: title, language: language, isRightToLeft: isRightToLeft, stylesheetHref: "style.css", body: body)
    }

    static func ncx(identifier: String, title: String, depth: Int, navPoints: String) -> String {
        xmlDeclaration + """
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head>
            <meta name="dtb:uid" content="urn:uuid:\(identifier)"/>
            <meta name="dtb:depth" content="\(depth)"/>
            <meta name="dtb:totalPageCount" content="0"/>
            <meta name="dtb:maxPageNumber" content="0"/>
          </head>
          <docTitle><text>\(XMLEscaping.escape(title))</text></docTitle>
          <navMap>
        \(navPoints)
          </navMap>
        </ncx>

        """
    }
}
