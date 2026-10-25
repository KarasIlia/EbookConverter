import Foundation
import Testing
@testable import EbookCore

@Suite struct EPUBWriterTests {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEPUB(_ document: BookDocument = FixtureFactory.sampleDocument(), withCover: Bool = true) throws -> Data {
        let cover = withCover ? FixtureFactory.pngImage(width: 4, height: 6, id: "cover-src") : nil
        return try EPUBWriter(modified: Self.fixedDate).write(document, cover: cover)
    }

    private func withTempFile<T>(_ data: Data, _ body: (URL) throws -> T) throws -> T {
        let url = URL.temporaryDirectory.appending(path: "epubtest-\(UUID().uuidString).epub")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private func listing(_ epub: Data) throws -> [String] {
        try withTempFile(epub) { url in
            let result = try run("/usr/bin/unzip", ["-Z1", url.path(percentEncoded: false)])
            return String(decoding: result.output, as: UTF8.self).split(separator: "\n").map(String.init)
        }
    }

    private func extract(_ epub: Data, _ path: String) throws -> Data {
        try withTempFile(epub) { url in
            try run("/usr/bin/unzip", ["-p", url.path(percentEncoded: false), path]).output
        }
    }

    @Test func escapesSpecialAndInvalidChars() {
        #expect(XMLEscaping.escape("a&b<c>\"d'\u{0B}e") == "a&amp;b&lt;c&gt;&quot;d&apos;e")
        #expect(XMLEscaping.escape("x\u{00}\u{08}\u{0C}\u{0E}\u{1F}\u{FFFE}\u{FFFF}y\n\t\r") == "xy\n\t\r")
        #expect(XMLEscaping.escape("Привет 日本語") == "Привет 日本語")
    }

    @Test func archiveContainsExpectedEntries() throws {
        let names = try listing(makeEPUB())
        #expect(names.first == "mimetype")
        #expect(Set(names) == [
            "mimetype", "META-INF/container.xml", "OEBPS/content.opf", "OEBPS/nav.xhtml", "OEBPS/toc.ncx",
            "OEBPS/style.css", "OEBPS/text/cover.xhtml", "OEBPS/images/cover.png",
            "OEBPS/text/chapter-001.xhtml", "OEBPS/text/chapter-002.xhtml",
            "OEBPS/text/chapter-003.xhtml", "OEBPS/text/chapter-004.xhtml",
            "OEBPS/images/img1.png",
        ])
    }

    @Test func noCoverMeansNoCoverFiles() throws {
        let epub = try makeEPUB(withCover: false)
        let names = try listing(epub)
        #expect(!names.contains("OEBPS/text/cover.xhtml"))
        #expect(!names.contains { $0.contains("cover.png") })
        let opf = String(decoding: try extract(epub, "OEBPS/content.opf"), as: UTF8.self)
        #expect(!opf.contains("cover-image"))
    }

    @Test func allXMLFilesAreWellFormed() throws {
        let epub = try makeEPUB()
        let xmlNames = try listing(epub).filter { name in [".opf", ".xhtml", ".ncx", ".xml"].contains { ext in name.hasSuffix(ext) } }
        #expect(xmlNames.count >= 8)
        for name in xmlNames {
            let data = try extract(epub, name)
            #expect((try? XMLDocument(data: data, options: [])) != nil, "\(name) is not well-formed")
        }
        let chapter = String(decoding: try extract(epub, "OEBPS/text/chapter-002.xhtml"), as: UTF8.self)
        #expect(chapter.contains("Fish &amp; &lt;chips&gt;"))
        #expect(chapter.contains("<strong>bold</strong>"))
        let chapter3 = String(decoding: try extract(epub, "OEBPS/text/chapter-003.xhtml"), as: UTF8.self)
        #expect(chapter3.contains("Verticaltab removed."))
        #expect(chapter3.contains("<h3>Subheading</h3>"))
    }

    @Test func manifestMatchesFiles() throws {
        let epub = try makeEPUB()
        let names = Set(try listing(epub))
        let opf = try XMLDocument(data: extract(epub, "OEBPS/content.opf"), options: [])
        let hrefs = try opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']/@href").compactMap(\.stringValue)
        #expect(!hrefs.isEmpty)
        for href in hrefs {
            #expect(names.contains("OEBPS/" + href), "\(href) missing from archive")
        }
        let expected = names.filter { !$0.hasPrefix("META-INF/") && $0 != "mimetype" && $0 != "OEBPS/content.opf" }
        #expect(Set(hrefs.map { "OEBPS/" + $0 }) == expected)

        let xml = String(decoding: try extract(epub, "OEBPS/content.opf"), as: UTF8.self)
        #expect(xml.contains("urn:uuid:11111111-2222-3333-4444-555555555555"))
        #expect(xml.contains("<meta property=\"dcterms:modified\">2023-11-14T22:13:20Z</meta>"))
        #expect(xml.contains("<meta name=\"cover\" content=\"cover-image\"/>"))
        #expect(xml.contains("properties=\"cover-image\""))
        #expect(xml.contains("<spine toc=\"ncx\">\n    <itemref idref=\"cover\"/>"))
    }

    @Test func guideReferencesCoverOnlyWithCover() throws {
        let with = String(decoding: try extract(makeEPUB(), "OEBPS/content.opf"), as: UTF8.self)
        #expect(with.contains("<reference type=\"cover\" title=\"Cover\" href=\"text/cover.xhtml\"/>"))
        let without = String(decoding: try extract(makeEPUB(withCover: false), "OEBPS/content.opf"), as: UTF8.self)
        #expect(!without.contains("<guide>"))
    }

    @Test func allInternalLinksResolve() throws {
        let epub = try makeEPUB()
        let names = Set(try listing(epub))
        let pages = names.filter { $0.hasSuffix(".xhtml") }
        #expect(pages.count == 6)
        for page in pages {
            let doc = try XMLDocument(data: extract(epub, page), options: [])
            let refs = try doc.nodes(forXPath: "//*[local-name()='link']/@href | //*[local-name()='img']/@src").compactMap(\.stringValue)
            #expect(!refs.isEmpty)
            let dir = page.split(separator: "/").dropLast().map(String.init)
            for ref in refs {
                var parts = dir
                for part in ref.split(separator: "/") {
                    if part == ".." { _ = parts.popLast() } else if part != "." { parts.append(String(part)) }
                }
                #expect(names.contains(parts.joined(separator: "/")), "\(page) -> \(ref) unresolved")
            }
        }
    }

    @Test func navNestsParts() throws {
        let epub = try makeEPUB()
        let nav = try XMLDocument(data: extract(epub, "OEBPS/nav.xhtml"), options: [])
        let top = try nav.nodes(forXPath: "//*[local-name()='nav']/*[local-name()='ol']/*[local-name()='li']")
        #expect(top.count == 2)
        let inner = try top[0].nodes(forXPath: "./*[local-name()='ol']/*[local-name()='li']")
        #expect(inner.count == 2)
        let ncx = try XMLDocument(data: extract(epub, "OEBPS/toc.ncx"), options: [])
        let orders = try ncx.nodes(forXPath: "//*[local-name()='navPoint']/@playOrder").compactMap(\.stringValue)
        #expect(orders == ["1", "2", "3", "4"])
        let nested = try ncx.nodes(forXPath: "/*/*[local-name()='navMap']/*[local-name()='navPoint'][1]/*[local-name()='navPoint']")
        #expect(nested.count == 2)
    }

    @Test func untitledChaptersGetFallbackLabels() throws {
        let document = BookDocument(
            metadata: BookMetadata(title: "Book", author: "", language: "en"),
            chapters: [
                Chapter(blocks: [.paragraph([InlineRun("one")])]),
                Chapter(blocks: [.paragraph([InlineRun("two")])]),
            ]
        )
        let epub = try makeEPUB(document, withCover: false)
        let nav = String(decoding: try extract(epub, "OEBPS/nav.xhtml"), as: UTF8.self)
        #expect(nav.contains(">Book</a>"))
        #expect(nav.contains(">\u{2026}</a>"))
        let chapter = String(decoding: try extract(epub, "OEBPS/text/chapter-001.xhtml"), as: UTF8.self)
        #expect(!chapter.contains("<h1>"))
    }

    @Test func rtlBookMarked() throws {
        let arabic = try makeEPUB(FixtureFactory.sampleDocument(language: "ar"))
        let opf = String(decoding: try extract(arabic, "OEBPS/content.opf"), as: UTF8.self)
        #expect(opf.contains("<spine toc=\"ncx\" page-progression-direction=\"rtl\">"))
        let chapter = try XMLDocument(data: extract(arabic, "OEBPS/text/chapter-002.xhtml"), options: [])
        #expect(chapter.rootElement()?.attribute(forName: "dir")?.stringValue == "rtl")
        #expect(chapter.rootElement()?.attribute(forName: "lang")?.stringValue == "ar")

        let german = try makeEPUB(FixtureFactory.sampleDocument(language: "de"))
        let germanOPF = String(decoding: try extract(german, "OEBPS/content.opf"), as: UTF8.self)
        #expect(!germanOPF.contains("page-progression-direction"))
        let germanChapter = try XMLDocument(data: extract(german, "OEBPS/text/chapter-002.xhtml"), options: [])
        #expect(germanChapter.rootElement()?.attribute(forName: "dir") == nil)
        #expect(germanChapter.rootElement()?.attribute(forName: "xml:lang")?.stringValue == "de")
    }

    @Test func blankTitleAndLanguageGetFallbacks() throws {
        var document = FixtureFactory.sampleDocument()
        document.metadata = BookMetadata(title: "  ", author: "", language: " ")
        let opf = String(decoding: try extract(makeEPUB(document), "OEBPS/content.opf"), as: UTF8.self)
        #expect(opf.contains("<dc:title>Book</dc:title>"))
        #expect(opf.contains("<dc:language>und</dc:language>"))
        #expect(opf.contains("xml:lang=\"und\""))
    }

    @Test func outputIsDeterministic() throws {
        #expect(try makeEPUB() == makeEPUB())
    }

    private static func javaPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let override = env["EPUBCHECK_JAVA"] { return override }
        if let home = env["JAVA_HOME"], FileManager.default.isExecutableFile(atPath: home + "/bin/java") {
            return home + "/bin/java"
        }
        let brew = "/opt/homebrew/opt/openjdk/bin/java"
        return FileManager.default.isExecutableFile(atPath: brew) ? brew : "/usr/bin/java"
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["EPUBCHECK_JAR"] != nil),
          arguments: ["cover", "noCover", "rtl", "blankTitle"])
    func epubcheckPasses(variant: String) throws {
        let jar = ProcessInfo.processInfo.environment["EPUBCHECK_JAR"] ?? ""
        let epub = switch variant {
        case "noCover": try makeEPUB(withCover: false)
        case "rtl": try makeEPUB(FixtureFactory.sampleDocument(language: "ar"))
        case "blankTitle":
            try makeEPUB(BookDocument(metadata: BookMetadata(title: " ", author: " ", language: ""), chapters: FixtureFactory.sampleDocument().chapters))
        default: try makeEPUB()
        }
        try withTempFile(epub) { url in
            let result = try run(Self.javaPath(), ["-jar", jar, "--failonwarnings", url.path(percentEncoded: false)])
            let output = String(decoding: result.output, as: UTF8.self)
            #expect(result.status == 0, "\(output)")
        }
    }
}
