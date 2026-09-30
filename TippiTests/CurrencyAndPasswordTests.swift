import SwiftUI
import XCTest
@testable import Tippi

final class CurrencyParserTests: XCTestCase {
    private func parse(_ text: String) -> MoneyAmount? { CurrencyParser.parse(text) }

    /// The examples from Michael's request (2026-09-28).
    func testRequestExamples() {
        XCTAssertEqual(parse("23€"), MoneyAmount(value: 23, code: "EUR"))
        XCTAssertEqual(parse("23 €"), MoneyAmount(value: 23, code: "EUR"))
        XCTAssertEqual(parse("62,700 円"), MoneyAmount(value: 62_700, code: "JPY"))
        XCTAssertEqual(parse("USD 1,100"), MoneyAmount(value: 1_100, code: "USD"))
        XCTAssertEqual(parse("1.100 TWD"), MoneyAmount(value: 1_100, code: "TWD"))
        XCTAssertEqual(parse("250 AED"), MoneyAmount(value: 250, code: "AED"))
    }

    func testSymbols() {
        XCTAssertEqual(parse("$9.99")?.code, "USD")
        XCTAssertEqual(parse("£5")?.code, "GBP")
        XCTAssertEqual(parse("¥300")?.code, "JPY")
        XCTAssertEqual(parse("88 元")?.code, "CNY")
        XCTAssertEqual(parse("₡5.000")?.code, "CRC")
        XCTAssertEqual(parse("NT$ 500")?.code, "TWD")
        XCTAssertEqual(parse("Fr. 12.50")?.code, "CHF")
    }

    func testLowercaseCodeAndSurroundingWhitespace() {
        XCTAssertEqual(parse("  12 eur\n"), MoneyAmount(value: 12, code: "EUR"))
    }

    func testDecimalVersusThousands() {
        XCTAssertEqual(CurrencyParser.parseNumber("1,5"), 1.5)
        XCTAssertEqual(CurrencyParser.parseNumber("9.99"), 9.99)
        XCTAssertEqual(CurrencyParser.parseNumber("1,100"), 1_100)
        XCTAssertEqual(CurrencyParser.parseNumber("1.100"), 1_100)
        XCTAssertEqual(CurrencyParser.parseNumber("1.234,50"), 1_234.5)
        XCTAssertEqual(CurrencyParser.parseNumber("1,234.50"), 1_234.5)
        XCTAssertEqual(CurrencyParser.parseNumber("1.234.567"), 1_234_567)
        XCTAssertEqual(CurrencyParser.parseNumber("1 234"), 1_234)
        XCTAssertEqual(CurrencyParser.parseNumber("1'234.50"), 1_234.5)
    }

    func testNotAnAmount() {
        XCTAssertNil(parse("Kino heute Abend"))
        XCTAssertNil(parse("23"), "a number without a currency is no amount")
        XCTAssertNil(parse("€ 23 €"), "currency on both sides")
        XCTAssertNil(parse("23 kr"), "kr is ambiguous (SEK/NOK/DKK)")
        XCTAssertNil(parse("23 XYZ"), "unknown code")
        XCTAssertNil(parse("Preis 23 €"), "a word in front is not a currency")
        XCTAssertNil(parse(String(repeating: "1", count: 41) + " €"), "longer than the cap")
    }
}

final class ExchangeRateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_600_000)

    private func response(_ extra: String = "", base: String = "EUR", result: String = "success") -> Data {
        let rates = CurrencyCatalog.codes.map { "\"\($0)\": \($0 == "EUR" ? "1" : "2.5")" }.joined(separator: ",")
        return Data("""
        {"result":"\(result)","base_code":"\(base)","time_next_update_unix":1790641741,\(extra)
         "rates":{\(rates)}}
        """.utf8)
    }

    func testParsesValidResponse() throws {
        let table = try XCTUnwrap(ExchangeRateTable.parse(response(), now: now))
        XCTAssertEqual(table.rates["USD"], 2.5)
        XCTAssertEqual(table.nextUpdate, Date(timeIntervalSince1970: 1_790_641_741))
    }

    func testRejectsWrongBaseOrError() {
        XCTAssertNil(ExchangeRateTable.parse(response(base: "USD"), now: now))
        XCTAssertNil(ExchangeRateTable.parse(response(result: "error"), now: now))
        XCTAssertNil(ExchangeRateTable.parse(Data("not json".utf8), now: now))
        XCTAssertNil(ExchangeRateTable.parse(Data(count: ExchangeRateTable.maxResponseBytes + 1), now: now))
    }

    func testDropsInvalidRates() throws {
        let data = Data("""
        {"result":"success","base_code":"EUR","time_next_update_unix":1790641741,
         "rates":{\(CurrencyCatalog.codes.map { "\"\($0)\": 1" }.joined(separator: ",")),"usd":2,"BAD1":3,"XXX":-1,"YYY":0}}
        """.utf8)
        let table = try XCTUnwrap(ExchangeRateTable.parse(data, now: now))
        XCTAssertNil(table.rates["usd"])
        XCTAssertNil(table.rates["BAD1"])
        XCTAssertNil(table.rates["XXX"])
        XCTAssertNil(table.rates["YYY"])
    }

    func testFarFutureNextUpdateIsCapped() throws {
        let data = Data("""
        {"result":"success","base_code":"EUR","time_next_update_unix":9999999999,
         "rates":{\(CurrencyCatalog.codes.map { "\"\($0)\": 1" }.joined(separator: ","))}}
        """.utf8)
        let table = try XCTUnwrap(ExchangeRateTable.parse(data, now: now))
        XCTAssertLessThanOrEqual(table.nextUpdate, now.addingTimeInterval(48 * 3600))
    }

    func testConvertsThroughEURBase() {
        let table = ExchangeRateTable(rates: ["EUR": 1, "USD": 1.1385, "JPY": 179.28], fetchedAt: now, nextUpdate: now)
        let usd = table.convert(MoneyAmount(value: 23, code: "EUR"), to: "USD")
        XCTAssertEqual(usd ?? 0, 26.1855, accuracy: 0.0001)
        let eur = table.convert(MoneyAmount(value: 62_700, code: "JPY"), to: "EUR")
        XCTAssertEqual(eur ?? 0, 349.73, accuracy: 0.01)
        XCTAssertNil(table.convert(MoneyAmount(value: 1, code: "EUR"), to: "CRC"))
    }

    // MARK: - Fetch policy

    private func table(fetched: TimeInterval, next: TimeInterval) -> ExchangeRateTable {
        ExchangeRateTable(rates: ["EUR": 1], fetchedAt: now.addingTimeInterval(fetched), nextUpdate: now.addingTimeInterval(next))
    }

    func testFreshCacheIsUsedWithoutRequest() {
        XCTAssertEqual(ExchangeRateService.decide(table: table(fetched: -600, next: 3600), now: now,
                                                  lastAttempt: nil, blockedUntil: nil), .useCache)
    }

    func testStaleCacheTriggersFetch() {
        XCTAssertEqual(ExchangeRateService.decide(table: table(fetched: -90_000, next: -10), now: now,
                                                  lastAttempt: nil, blockedUntil: nil), .fetch)
        XCTAssertEqual(ExchangeRateService.decide(table: nil, now: now, lastAttempt: nil, blockedUntil: nil), .fetch)
    }

    /// Clicking again right after a failed request must not hit the API again.
    func testAtMostOneAttemptPerHour() {
        XCTAssertEqual(ExchangeRateService.decide(table: table(fetched: -90_000, next: -10), now: now,
                                                  lastAttempt: now.addingTimeInterval(-60), blockedUntil: nil), .useCache)
        XCTAssertEqual(ExchangeRateService.decide(table: nil, now: now,
                                                  lastAttempt: now.addingTimeInterval(-60), blockedUntil: nil), .unavailable)
    }

    func testRateLimitPause() {
        XCTAssertEqual(ExchangeRateService.decide(table: nil, now: now, lastAttempt: nil,
                                                  blockedUntil: now.addingTimeInterval(60)), .unavailable)
    }

    func testCacheOlderThanAWeekIsNotUsedWhileThrottled() {
        XCTAssertEqual(ExchangeRateService.decide(table: table(fetched: -8 * 86_400, next: -7 * 86_400), now: now,
                                                  lastAttempt: now.addingTimeInterval(-60), blockedUntil: nil), .unavailable)
    }
}

final class CurrencyFormatterTests: XCTestCase {
    private let german = Locale(identifier: "de_DE")

    func testAppendsConversion() {
        XCTAssertEqual(CurrencyFormatter.appending(26.1855, code: "USD", to: "23 €", locale: german),
                       "23 € (≈ 26,19\u{00A0}$)", "formatter keeps amount and symbol together")
    }

    func testKeepsTrailingWhitespaceAtTheEnd() {
        XCTAssertEqual(CurrencyFormatter.appending(26.1855, code: "USD", to: "23 € ", locale: german),
                       "23 € (≈ 26,19\u{00A0}$) ")
    }

    func testTargetsExcludeSourceCurrency() {
        let targets = CurrencySettings.targets(for: MoneyAmount(value: 1, code: CurrencySettings.favorites.first ?? "USD"))
        XCTAssertFalse(targets.contains(CurrencySettings.favorites.first ?? "USD"))
    }
}

/// Ergebnis anzeigen + kopieren (Standard) oder zusätzlich anhängen. Über `store`, nie `.standard`.
@MainActor
final class CurrencyResultModeTests: XCTestCase {
    private let german = Locale(identifier: "de_DE")
    private let suites = ThrowawayDefaults()

    override func setUp() {
        super.setUp()
        CurrencySettings.store = suites.make()
    }

    override func tearDown() {
        CurrencySettings.store = .standard
        suites.removeAll()
        super.tearDown()
    }

    /// Seit 2.21: anzeigen und kopieren. Michael lief ohne gespeicherten Wert im alten
    /// Standard und sah nur „In USD umrechnen".
    func testCopyIsTheDefault() {
        XCTAssertEqual(CurrencySettings.resultMode, .copy)
    }

    func testModeRoundTripAndUnknownValueFallsBack() {
        CurrencySettings.resultMode = .append
        XCTAssertEqual(CurrencySettings.resultMode, .append)
        CurrencySettings.store.set("irgendwas", forKey: CurrencySettings.resultModeKey)
        XCTAssertEqual(CurrencySettings.resultMode, .copy)
    }

    /// Die Bindung, die der Picker benutzt, schreibt den Schlüssel sofort.
    func testPickerBindingWritesTheKey() {
        var shown = CurrencyResultMode.copy
        let binding = CurrencyFavoritesSection.modeBinding(Binding(get: { shown }, set: { shown = $0 }))
        binding.wrappedValue = .append
        XCTAssertEqual(shown, .append)
        XCTAssertEqual(CurrencySettings.store.string(forKey: CurrencySettings.resultModeKey), "append")
        binding.wrappedValue = .copy
        XCTAssertEqual(CurrencySettings.store.string(forKey: CurrencySettings.resultModeKey), "copy")
    }

    /// Beide Modi kopieren den Betrag (nur Zahl + Währung); nur „anhängen" ändert den Text.
    func testAppendModeReplacesTextAndCopiesAmount() {
        let outcome = CurrencyOutcome.make(text: "23 €", converted: 26.1855, code: "USD", mode: .append, locale: german)
        XCTAssertEqual(outcome.replacement, "23 € (≈ 26,19\u{00A0}$)")
        XCTAssertEqual(outcome.amount, "26,19\u{00A0}$")
    }

    func testCopyModeLeavesTextAndCopiesAmount() {
        let outcome = CurrencyOutcome.make(text: "23 € ", converted: 26.1855, code: "USD", mode: .copy, locale: german)
        XCTAssertNil(outcome.replacement)
        XCTAssertEqual(outcome.amount, "26,19\u{00A0}$")
    }

    /// Der Hinweis nennt das Ergebnis, nie den Aktionsnamen.
    func testHintShowsTheResultInBothModes() {
        let copy = CurrencyOutcome.make(text: "23 €", converted: 26.1855, code: "USD", mode: .copy, locale: german)
        let append = CurrencyOutcome.make(text: "23 €", converted: 26.1855, code: "USD", mode: .append, locale: german)
        XCTAssertTrue(copy.hint.contains("26,19"))
        XCTAssertTrue(append.hint.contains("26,19"))
        XCTAssertNotEqual(copy.hint, append.hint)
        XCTAssertFalse(append.hint.contains("USD"))
    }
}

final class PasswordGeneratorTests: XCTestCase {
    func testLengthAndEveryClass() {
        for _ in 0..<500 {
            let password = PasswordGenerator.generate()
            XCTAssertEqual(password.count, 12)
            for characterClass in PasswordGenerator.classes {
                XCTAssertTrue(password.contains(where: characterClass.contains), "missing class in \(password.count)-char password")
            }
        }
    }

    func testOnlyAllowedCharactersAndNoLookAlikes() {
        let allowed = Set(PasswordGenerator.classes.flatMap { $0 })
        for character in "IOlo01" { XCTAssertFalse(allowed.contains(character), "look-alike \(character)") }
        for _ in 0..<500 {
            XCTAssertTrue(PasswordGenerator.generate().allSatisfy(allowed.contains))
        }
    }

    func testSymbolSetIsMichaelsList() {
        XCTAssertEqual(String(PasswordGenerator.symbols), "/()=?&%$§\"!-_:;")
    }

    /// Mandatory characters must not always sit in the first four places.
    func testMandatoryCharactersAreShuffled() {
        var digitPositions = Set<Int>()
        for _ in 0..<300 {
            let password = Array(PasswordGenerator.generate())
            if let index = password.firstIndex(where: PasswordGenerator.digits.contains) { digitPositions.insert(index) }
        }
        XCTAssertGreaterThan(digitPositions.count, 6)
    }

    func testPasswordsDiffer() {
        let passwords = Set((0..<200).map { _ in PasswordGenerator.generate() })
        XCTAssertEqual(passwords.count, 200)
    }
}
