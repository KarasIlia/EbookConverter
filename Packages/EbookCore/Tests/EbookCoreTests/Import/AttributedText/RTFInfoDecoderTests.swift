import Foundation
import Testing
@testable import EbookCore

@Suite struct RTFInfoDecoderTests {
    private func rtf(_ header: String, info: Data) -> Data {
        var data = Data(header.utf8)
        data.append(Data("{\\info".utf8))
        data.append(info)
        data.append(Data("}\\pard body\\par}".utf8))
        return data
    }

    /// An RTF `\\uN` escape; built at runtime so the source never contains a literal backslash-u sequence.
    private func u(_ value: Int) -> String { "\\" + "u" + String(value) }

    @Test func rtfMetadataDecodedFromDeclaredCodepage() throws {
        // The user's sample: `\ansicpg` with no number, codepage only via the default font's \fcharset204.
        let title = "Хочу в программисты! Основы разработки для начинающих"
        var info = Data("{\\title ".utf8)
        info.append(try #require(title.data(using: .windowsCP1251)))
        info.append(Data("}{\\author ".utf8))
        info.append(try #require("Иван Петров ".data(using: .windowsCP1251)))
        info.append(Data("}".utf8))
        let header = #"{\rtf1\ansi\ansicpg\deff0\deflang1049{\fonttbl{\f0\fswiss\fprq2\fcharset204{\*\fname Arial CYR;}Arial;}{\f1\froman\fcharset0 Times;}}"#
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: info))
        #expect(metadata.title == title)
        #expect(metadata.author == "Иван Петров")
    }

    @Test func ansiCodepageWinsAndHexEscapesDecode() {
        let header = #"{\rtf1\ansi\ansicpg1252\deff1{\fonttbl\f0\fnil\fcharset204 A;\f1\fnil\fcharset238 B;}"#
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: Data(#"{\title Caf\'e9 \{cr\'e8me\} \\ br\'fbl\'e9e}"#.utf8)))
        #expect(metadata.title == "Café {crème} \\ brûlée")
        #expect(metadata.author == nil)
    }

    @Test func defaultFontCharsetSelectsCodepage() {
        // No \ansicpg: \deff1 points at the CP1250 font.
        let header = #"{\rtf1\ansi\deff1{\fonttbl\f0\fnil\fcharset204 A;\f1\fnil\fcharset238 B;}"#
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: Data(#"{\author \'8ailer \'9a}"#.utf8)))
        #expect(metadata.author == "Šiler š")
    }

    @Test func unicodeEscapesSkipFallbackCharacters() {
        let header = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl\f0\fnil\fcharset0 A;}"#
        let info = Data(("{\\title A" + u(4193) + "?B\\u-3913?C\\uc2" + u(1046) + "??D\\uc0" + u(1047) + " E\\b bold\\b0}").utf8)
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: info))
        #expect(metadata.title == "A\u{1061}B\u{F0B7}C\u{0416}D\u{0417}Ebold")
    }

    @Test func surrogatePairsCombine() {
        let header = #"{\rtf1\ansi\ansicpg1252{\fonttbl\f0\fnil A;}"#
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: Data(#"{\title x\u-10179?\u-8704?y}"#.utf8)))
        #expect(metadata.title == "x\u{1F600}y")
    }

    @Test func missingOrEmptyInfo() {
        #expect(RTFInfoDecoder.metadata(fromRTF: Data(#"{\rtf1\ansi body\par}"#.utf8)) == (nil, nil))
        let header = #"{\rtf1\ansi"#
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: Data(#"{\title   }{\*\company X}"#.utf8)))
        #expect(metadata.title == nil)
        #expect(RTFInfoDecoder.metadata(fromRTF: Data("not rtf".utf8)) == (nil, nil))
    }

    @Test func typographicControlWordsMapToCharacters() {
        let header = #"{\rtf1\ansi\ansicpg1252{\fonttbl\f0\fnil A;}"#
        let info = Data(#"{\title A\endash B\emdash C \lquote q\rquote  \ldblquote dq\rdblquote \bullet\tab x\~y}"#.utf8)
        let metadata = RTFInfoDecoder.metadata(fromRTF: rtf(header, info: info))
        #expect(metadata.title == "A–B—C ‘q’ “dq”• x\u{00A0}y")
    }
}
