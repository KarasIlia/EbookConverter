import Testing
@testable import EbookCore

@Suite struct LineJoinerTests {
    @Test func latinLinesJoinWithSpace() {
        #expect(LineJoiner.joined("one line", "next line") == "one line next line")
    }

    @Test func trailingWhitespaceIsCollapsed() {
        #expect(LineJoiner.joined("one line  ", "next") == "one line next")
    }

    @Test func cjkLinesJoinWithoutSpace() {
        #expect(LineJoiner.joined("正文第一行", "第二行。") == "正文第一行第二行。")
        #expect(LineJoiner.joined("吾輩は猫である。", "名前はまだ無い。") == "吾輩は猫である。名前はまだ無い。")
    }

    @Test func southeastAsianScriptsJoinWithoutSpace() {
        #expect(LineJoiner.joined("ภาษาไทย", "ภาษาไทย") == "ภาษาไทยภาษาไทย")
        #expect(LineJoiner.joined("ភាសាខ្មែរ", "ភាសា") == "ភាសាខ្មែរភាសា")
        #expect(LineJoiner.joined("မြန်မာ", "စာ") == "မြန်မာစာ")
        #expect(LineJoiner.joined("ພາສາລາວ", "ພາສາ") == "ພາສາລາວພາສາ")
    }

    @Test func mixedScriptsKeepSpace() {
        #expect(LineJoiner.joined("中文", "English") == "中文 English")
        #expect(LineJoiner.joined("English", "中文") == "English 中文")
    }

    @Test func hyphenBeforeLowercaseMerges() {
        #expect(LineJoiner.joined("a con-", "tinued word") == "a continued word")
        #expect(LineJoiner.joined("пере-", "нос") == "перенос")
    }

    @Test func hyphenBeforeUppercaseIsKept() {
        #expect(LineJoiner.joined("Jean-", "Paul") == "Jean-Paul")
    }

    @Test func detachedDashKeepsSpace() {
        #expect(LineJoiner.joined("word -", "next") == "word - next")
    }

    @Test func softHyphenIsDropped() {
        #expect(LineJoiner.joined("con\u{AD}", "tinued") == "continued")
    }
}
