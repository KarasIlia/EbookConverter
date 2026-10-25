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
}
