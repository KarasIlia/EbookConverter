import Testing
import Foundation
@testable import EbookCore

@Suite struct TextEncodingTests {
    static let russian = String(repeating: "Это длинный абзац русского текста для проверки определения кодировки. ", count: 4)
    static let german = String(repeating: "Größere Mäuse überqueren die Straße, weil süße Äpfel dort wachsen. ", count: 3)
    static let japanese = String(repeating: "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。", count: 3)

    @Test(arguments: [
        (russian, String.Encoding.windowsCP1251),
        (german, String.Encoding.windowsCP1252),
        (japanese, String.Encoding.shiftJIS),
    ])
    func decodesLegacyEncodings(text: String, encoding: String.Encoding) throws {
        let data = try #require(text.data(using: encoding))
        #expect(TextEncodingDetector.decode(data) == text)
    }

    @Test func decodesUTF16BOM() throws {
        let text = "Привет, мир! Hello"
        var data = Data([0xFF, 0xFE])
        data.append(try #require(text.data(using: .utf16LittleEndian)))
        #expect(TextEncodingDetector.decode(data) == text)
        var big = Data([0xFE, 0xFF])
        big.append(try #require(text.data(using: .utf16BigEndian)))
        #expect(TextEncodingDetector.decode(big) == text)
    }

    @Test func decodesUTF8WithAndWithoutBOM() throws {
        let text = "Grüße 東京"
        let plain = try #require(text.data(using: .utf8))
        #expect(TextEncodingDetector.decode(plain) == text)
        #expect(TextEncodingDetector.decode(Data([0xEF, 0xBB, 0xBF]) + plain) == text)
    }

    @Test func repairsMacRomanMojibakeGerman() throws {
        let original = "Grüße aus München"
        let data = try #require(original.data(using: .windowsCP1252))
        let broken = try #require(String(data: data, encoding: .macOSRoman))
        #expect(broken != original)
        #expect(MojibakeRepair.repair(broken) == original)
    }

    @Test func repairsMacCyrillicMojibake() throws {
        let original = "Хочу в программисты!"
        let macCyrillic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.macCyrillic.rawValue)))
        let data = try #require(original.data(using: .windowsCP1251))
        let broken = try #require(String(data: data, encoding: macCyrillic))
        #expect(broken != original)
        #expect(MojibakeRepair.repair(broken) == original)
        #expect(MojibakeRepair.repair("’очу в программисты! ќсновы") == "Хочу в программисты! Основы")
    }

    @Test(arguments: [
        "Hello – world", "Привет", "Grüße", "東京",
        "“Hello,” she said.", "“War and Peace”", "«Привет!»", "«Стой!» — «Нет!» — «Почему?»",
        "“HELLO WORLD”", "He said: “Stop.” Then left.", "L’été à Paris", "— Привет! — сказал он.",
        "«Война и мир»",
        String(repeating: "“Hello,” she said. “How are you?” “Fine, thanks,” he answered. ", count: 30),
        "“Where are you going?” she asked.\n\n“Home,” he said. “It is late.”\n\n«Привет!» — сказал он.",
    ])
    func repairLeavesNormalTextAlone(_ text: String) {
        #expect(MojibakeRepair.repair(text) == text)
    }

    @Test func repairsLongerMacCyrillicSample() {
        #expect(MojibakeRepair.repair("’очу в программисты! ќсновы разработки дл€ начинающих")
            == "Хочу в программисты! Основы разработки для начинающих")
    }
}
