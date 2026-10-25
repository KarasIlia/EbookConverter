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
}
