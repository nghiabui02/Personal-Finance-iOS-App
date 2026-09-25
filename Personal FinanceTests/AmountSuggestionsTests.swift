import Testing
@testable import My_Finance

struct AmountSuggestionsTests {

    @Test("shifts a single digit up to four digits first")
    func singleDigit() {
        #expect(amountSuggestions("5") == ["5.000", "50.000", "500.000"])
    }

    @Test("pads shorter inputs to four digits before scaling")
    func padsToFourDigits() {
        #expect(amountSuggestions("35") == ["3.500", "35.000", "350.000"])
        #expect(amountSuggestions("500") == ["5.000", "50.000", "500.000"])
    }

    @Test("shifts by a single power of ten once already four digits")
    func alreadyFourDigits() {
        #expect(amountSuggestions("5.000") == ["50.000", "500.000", "5.000.000"])
        #expect(amountSuggestions("12.345") == ["123.450", "1.234.500", "12.345.000"])
    }

    @Test("ignores existing grouping separators")
    func ignoresSeparators() {
        #expect(amountSuggestions("50.000") == amountSuggestions("50000"))
    }

    @Test("truncates suggestions that exceed the shared digit ceiling")
    func respectsMaxDigits() {
        // 5.000.000.000 has 10 digits, so only two shifts fit under 12.
        #expect(amountSuggestions("5.000.000.000") == ["50.000.000.000", "500.000.000.000"])
    }

    @Test("returns nothing for empty or zero input")
    func emptyOrZero() {
        #expect(amountSuggestions("").isEmpty)
        #expect(amountSuggestions("0").isEmpty)
        #expect(amountSuggestions("abc").isEmpty)
    }
}
