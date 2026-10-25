import NaturalLanguage

/// Detects the dominant language of a text.
public enum LanguageDetector {
    /// Longest stretch of one paragraph given to the recognizer.
    private static let sampleLength = 2000
    /// Paragraphs sampled from each of the start, middle and end of the text.
    private static let paragraphsPerRegion = 20
    private static let minimumConfidence = 0.5

    /// BCP-47 tag of the dominant language, or `nil` when the recognizer is not confident enough.
    ///
    /// Paragraphs vote, weighted by length × confidence, so one misleading line (a recognizer reads
    /// some names as another language) cannot decide the whole book. The winner's weight must reach
    /// `minimumConfidence` of all voting characters.
    public static func language(of text: String) -> String? {
        var votes: [NLLanguage: Double] = [:]
        var totalCharacters = 0
        for paragraph in sampledParagraphs(of: text) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(paragraph)
            guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { continue }
            votes[language, default: 0] += Double(paragraph.count) * confidence
            totalCharacters += paragraph.count
        }
        guard totalCharacters > 0,
              let (language, weight) = votes.max(by: { $0.value < $1.value }),
              weight / Double(totalCharacters) >= minimumConfidence else { return nil }
        return language.rawValue
    }

    private static func sampledParagraphs(of text: String) -> [String] {
        let paragraphs = text.split(whereSeparator: \.isNewline)
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(sampleLength)) }
            .filter { !$0.isEmpty }
        let regionCount = paragraphsPerRegion * 3
        guard paragraphs.count > regionCount else { return paragraphs }
        let middle = (paragraphs.count - paragraphsPerRegion) / 2
        return Array(paragraphs.prefix(paragraphsPerRegion))
            + paragraphs[middle..<middle + paragraphsPerRegion]
            + paragraphs.suffix(paragraphsPerRegion)
    }
}
