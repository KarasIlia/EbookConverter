import NaturalLanguage

/// Detects the dominant language of a text.
public enum LanguageDetector {
    private static let sampleLength = 2000
    private static let minimumConfidence = 0.5

    /// BCP-47 tag of the dominant language, or `nil` when the recognizer is not confident enough.
    public static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(sampleLength)))
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence else { return nil }
        return language.rawValue
    }
}
