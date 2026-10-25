import Foundation

/// Language-independent recognition of "Part N" / "Chapter N" style heading lines.
///
/// All keyword tables are applied regardless of the book's language and are matched
/// case- and diacritic-insensitively. Supporting a new language means extending the tables only.
public enum HeadingPatterns {
    /// Keywords followed by a number, roman numeral or (ordinal/number) word that introduce a part.
    static let partKeywords: [String] = [
        "Часть", "Книга", "Частина", "Част",
        "Part", "Book", "Teil", "Buch", "Partie", "Livre", "Parte", "Libro",
        "Część", "Księga", "Deel", "Boek", "Del", "Bok", "Osa", "Kirja", "Rész", "Könyv",
        "Díl", "Kniha", "Kısım", "Μέρος", "Βιβλίο", "חלק", "ספר", "الجزء", "الكتاب",
    ]

    /// Keywords followed by a number, roman numeral or (ordinal/number) word that introduce a chapter.
    static let chapterKeywords: [String] = [
        "Глава", "Розділ", "Раздел", "Поглавље",
        "Chapter", "Kapitel", "Chapitre", "Capítulo", "Capitolo", "Capitol",
        "Rozdział", "Hoofdstuk", "Kapittel", "Luku", "Peatükk", "Fejezet", "Kapitola",
        "Poglavje", "Poglavlje", "Skyrius", "Nodaļa", "Bölüm", "Κεφάλαιο",
        "פרק", "الفصل", "باب", "فصل", "Bab", "Chương",
    ]

    /// Lines that are chapter headings on their own.
    static let standaloneChapterWords: [String] = [
        "Prologue", "Epilogue", "Introduction", "Preface", "Foreword", "Afterword", "Conclusion",
        "Пролог", "Эпилог", "Предисловие", "Введение", "Заключение", "Послесловие",
        "Епілог", "Передмова", "Вступ", "Післямова",
        "Prolog", "Epilog", "Vorwort", "Einleitung", "Nachwort",
        "Préface", "Avant-propos", "Postface", "Épilogue",
        "Prólogo", "Epílogo", "Prefacio", "Introducción",
        "Prefazione", "Prologo", "Epilogo", "Introduzione",
        "Przedmowa", "Wstęp", "Posłowie", "Voorwoord", "Inleiding", "Nawoord",
        "Πρόλογος", "Επίλογος", "序章", "序言", "前言", "后记", "後記", "終章", "序",
    ]

    private static let foldedParts = partKeywords.map(fold)
    private static let foldedChapters = chapterKeywords.map(fold)
    private static let foldedStandalone = Set(standaloneChapterWords.map(fold))

    /// Classifies a single line as a part or chapter heading, or `nil` if it matches no pattern.
    ///
    /// A keyword followed by a word (not a number or roman numeral) that ends in sentence
    /// punctuation (`Книга упала.`) is not a match here; see `match(_:)`.
    public static func partOrChapter(_ line: String) -> HeadingKind? {
        guard let result = match(line), !result.needsSupport else { return nil }
        return result.kind
    }

    /// Like `partOrChapter`, but also reports weak matches: keyword + word token on a line ending
    /// in sentence punctuation. Those (`needsSupport == true`) are headings only when another
    /// signal (markup hint, larger font, bold) confirms them.
    static func match(_ line: String) -> (kind: HeadingKind, needsSupport: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folded = fold(trimmed)
        let endsInSentence = trimmed.last.map(ScriptTraits.isSentenceTerminal) ?? false

        if let wordToken = keywordMatch(in: folded, keywords: foldedParts) {
            return (.part, wordToken && endsInSentence)
        }
        if let wordToken = keywordMatch(in: folded, keywords: foldedChapters) {
            return (.chapter, wordToken && endsInSentence)
        }
        if matchesCJKChapter(trimmed) || matchesKoreanChapter(trimmed) { return (.chapter, false) }
        if matchesStandalone(folded) { return (.chapter, false) }
        if isBareNumber(trimmed) || isRomanNumeral(trimmed) { return (.chapter, false) }
        return nil
    }

    // MARK: - Matching

    /// Case-, diacritic- and width-insensitive form. Turkish dotted/dotless I fold to plain `i`.
    private static func fold(_ string: String) -> String {
        string
            .replacing("İ", with: "i")
            .replacing("ı", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// `keyword` + whitespace + one token (digits or letters), then an allowed ending.
    /// Returns `nil` if there is no match, otherwise whether the token is a word
    /// (letters that are not a roman numeral) rather than a number.
    private static func keywordMatch(in folded: String, keywords: [String]) -> Bool? {
        for keyword in keywords where folded.hasPrefix(keyword) {
            var rest = folded.dropFirst(keyword.count)
            guard let first = rest.first, first.isWhitespace else { continue }
            rest = rest.drop(while: \.isWhitespace)
            let token: Substring
            let isWord: Bool
            if rest.first.map(isDecimalDigit) == true {
                token = rest.prefix(while: isDecimalDigit)
                isWord = false
            } else {
                token = rest.prefix(while: \.isLetter)
                isWord = !isRomanNumeral(token.uppercased())
            }
            guard !token.isEmpty else { continue }
            if isAllowedEnding(rest.dropFirst(token.count)) { return isWord }
        }
        return nil
    }

    /// Allowed text after the heading token: nothing, `.`/`:`, or a subtitle
    /// introduced by `. `/`: ` or a dash (` — Title`).
    private static func isAllowedEnding(_ rest: Substring) -> Bool {
        if rest.isEmpty || rest == "." || rest == ":" { return true }
        var remainder = rest
        var hadPunctuation = false
        if let first = remainder.first, first == "." || first == ":" {
            remainder = remainder.dropFirst()
            hadPunctuation = true
        }
        let afterSpace = remainder.drop(while: \.isWhitespace)
        guard afterSpace.count < remainder.count else { return false }
        if hadPunctuation, !afterSpace.isEmpty, !isDash(afterSpace.first) { return true }
        if isDash(afterSpace.first) {
            let subtitle = afterSpace.dropFirst()
            let trimmed = subtitle.drop(while: \.isWhitespace)
            return trimmed.count < subtitle.count && !trimmed.isEmpty
        }
        return false
    }

    private static func isDash(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "—" || character == "–" || character == "-"
    }

    private static let cjkNumerals: Set<Character> = Set("0123456789０１２３４５６７８９一二三四五六七八九十百千零〇两")
    private static let cjkChapterMarks: Set<Character> = ["章", "回", "节", "節"]
    /// `第` + numerals + `章/回/节/節`, optionally followed by a title that is not a sentence.
    private static func matchesCJKChapter(_ line: String) -> Bool {
        guard line.first == "第" else { return false }
        let afterPrefix = line.dropFirst()
        let numerals = afterPrefix.prefix(while: cjkNumerals.contains)
        guard !numerals.isEmpty else { return false }
        let afterNumerals = afterPrefix.dropFirst(numerals.count)
        guard let mark = afterNumerals.first, cjkChapterMarks.contains(mark) else { return false }
        return isTitleTail(afterNumerals.dropFirst())
    }

    /// `제 N 장` (spaces optional), optionally followed by a title that is not a sentence.
    private static func matchesKoreanChapter(_ line: String) -> Bool {
        guard line.first == "제" else { return false }
        var rest = line.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        let digits = rest.prefix(while: isDecimalDigit)
        guard !digits.isEmpty else { return false }
        rest = rest.dropFirst(digits.count)
        if rest.first == " " { rest = rest.dropFirst() }
        guard rest.first == "장" else { return false }
        return isTitleTail(rest.dropFirst())
    }

    private static func isTitleTail(_ tail: Substring) -> Bool {
        guard let last = tail.last else { return true }
        return !ScriptTraits.isSentenceTerminal(last)
    }

    private static func matchesStandalone(_ folded: String) -> Bool {
        if foldedStandalone.contains(folded) { return true }
        guard let last = folded.last, last == "." || last == ":" else { return false }
        return foldedStandalone.contains(String(folded.dropLast()))
    }

    private static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.numericType == .decimal }
    }

    /// One to three decimal digits, optionally followed by `.`.
    private static func isBareNumber(_ line: String) -> Bool {
        let body = line.hasSuffix(".") ? line.dropLast() : Substring(line)
        return (1...3).contains(body.count) && body.allSatisfy(isDecimalDigit)
    }

    private static let romanValues: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]

    /// A well-formed upper-case roman numeral (1...3999), optionally followed by `.`.
    private static func isRomanNumeral(_ line: String) -> Bool {
        let body = line.hasSuffix(".") ? String(line.dropLast()) : line
        guard !body.isEmpty, body.count <= 15, body.allSatisfy({ romanValues[$0] != nil }) else { return false }
        let value = romanValue(body)
        return (1...3999).contains(value) && canonicalRoman(value) == body
    }

    private static func romanValue(_ numeral: String) -> Int {
        let values = numeral.compactMap { romanValues[$0] }
        var total = 0
        for (index, value) in values.enumerated() {
            if index + 1 < values.count, value < values[index + 1] {
                total -= value
            } else {
                total += value
            }
        }
        return total
    }

    private static func canonicalRoman(_ value: Int) -> String {
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
            (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var remaining = value
        var result = ""
        for (amount, symbol) in table {
            while remaining >= amount {
                result += symbol
                remaining -= amount
            }
        }
        return result
    }
}
