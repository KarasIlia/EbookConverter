import Testing
@testable import EbookCore

@Suite struct LanguageDetectorTests {
    @Test(arguments: [
        (TextEncodingTests.russian, "ru"),
        (TextEncodingTests.german, "de"),
        (TextEncodingTests.japanese, "ja"),
        ("كان يا ما كان في قديم الزمان ملك عظيم يحكم مدينة جميلة على شاطئ البحر وكان الناس يحبونه كثيرا", "ar"),
    ])
    func detectsLanguages(text: String, code: String) {
        #expect(LanguageDetector.language(of: text) == code)
    }

    @Test func returnsNilForDigits() {
        #expect(LanguageDetector.language(of: "12345") == nil)
    }

    @Test func scriptTraits() {
        #expect(ScriptTraits.isCJK("東"))
        #expect(!ScriptTraits.isCJK("a"))
        #expect(ScriptTraits.isLowercaseLetter("ж"))
        #expect(!ScriptTraits.isLowercaseLetter("Ж"))
        for c in [".", "!", "?", "…", "。", "！", "？", "؟", "।"] as [Character] {
            #expect(ScriptTraits.isSentenceTerminal(c))
        }
        #expect(!ScriptTraits.isSentenceTerminal(","))
    }

    @Test func misleadingFirstParagraphDoesNotDecide() {
        // NLLanguageRecognizer reads the name line alone as Kazakh.
        let paragraphs = ["Джек Лондон – Мартин Иден"]
            + Array(repeating: "Вы не в состоянии управлять своей жизнью? Люди используют вас? Вам сложно произнести слово нет?", count: 20)
        #expect(LanguageDetector.language(of: paragraphs.joined(separator: "\n")) == "ru")
    }
}
