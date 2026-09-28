import Foundation
import os

/// Currency conversion for the selection bar and the hotkey popup.
/// Design and threat model: docs/SECURE-DESIGN-currency-password.md.

private let currencyLog = Logger(subsystem: "com.tippi.app", category: "currency")

struct MoneyAmount: Equatable {
    let value: Double
    /// ISO 4217 code, always one of `CurrencyCatalog.codes`.
    let code: String
}

enum CurrencyCatalog {
    /// The currencies offered as targets and accepted as codes in a selection.
    static let codes: [String] = [
        "EUR", "USD", "GBP", "CHF", "JPY", "CNY", "TWD", "HKD", "KRW", "INR",
        "AED", "CAD", "AUD", "NZD", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF",
        "TRY", "BRL", "MXN", "CRC", "THB", "SGD", "ZAR", "ILS",
    ]

    /// Symbols that name exactly one currency in practice. Ambiguous ones get
    /// the most common reading (`$` = USD, `¥` = JPY); `kr` is left out on
    /// purpose — SEK, NOK and DKK are equally likely.
    static let symbols: [String: String] = [
        "€": "EUR", "$": "USD", "US$": "USD", "£": "GBP", "¥": "JPY", "￥": "JPY",
        "円": "JPY", "元": "CNY", "₩": "KRW", "₹": "INR", "₺": "TRY", "₡": "CRC",
        "฿": "THB", "₪": "ILS", "zł": "PLN", "Kč": "CZK", "Ft": "HUF",
        "Fr.": "CHF", "NT$": "TWD", "HK$": "HKD", "A$": "AUD", "C$": "CAD",
        "NZ$": "NZD", "R$": "BRL", "S$": "SGD", "د.إ": "AED",
    ]

    static let defaultFavorites = ["USD", "CRC", "GBP", "CHF"]
}

enum CurrencySettings {
    static let favoritesKey = "currency.favorites"
    static let maxFavorites = 5

    static var favorites: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? CurrencyCatalog.defaultFavorites
            let valid = stored.filter(CurrencyCatalog.codes.contains)
            return Array(valid.prefix(maxFavorites))
        }
        set {
            let valid = newValue.filter(CurrencyCatalog.codes.contains)
            UserDefaults.standard.set(Array(valid.prefix(maxFavorites)), forKey: favoritesKey)
        }
    }

    /// Favorites minus the currency the selection is already in.
    static func targets(for amount: MoneyAmount) -> [String] {
        favorites.filter { $0 != amount.code }
    }
}

enum CurrencyParser {
    /// Longer selections are not "an amount" — and a short cap keeps the
    /// regular expression below far away from any backtracking cost.
    static let maxLength = 40

    private static let pattern = try? NSRegularExpression(
        pattern: #"^([^\d\s]{1,4})?\s?(\d[\d.,'   ]*)\s?([^\d\s]{1,4})?$"#
    )

    static func parse(_ text: String) -> MoneyAmount? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength, let pattern else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range) else { return nil }

        func group(_ index: Int) -> String? {
            guard let groupRange = Range(match.range(at: index), in: trimmed) else { return nil }
            return String(trimmed[groupRange])
        }
        let prefix = group(1)
        let suffix = group(3)
        // Exactly one side names the currency: "23 €" or "€ 23", never both.
        guard (prefix == nil) != (suffix == nil),
              let token = prefix ?? suffix,
              let code = currencyCode(for: token),
              let number = group(2),
              let value = parseNumber(number)
        else { return nil }
        return MoneyAmount(value: value, code: code)
    }

    static func currencyCode(for token: String) -> String? {
        if let code = CurrencyCatalog.symbols[token] { return code }
        let upper = token.uppercased()
        return CurrencyCatalog.codes.contains(upper) ? upper : nil
    }

    /// `1,100` / `1.100` / `62,700` → thousands; `1,5` / `9.99` → decimal.
    /// With both separators the last one is the decimal point (`1.234,50`).
    static func parseNumber(_ raw: String) -> Double? {
        let digits = raw.filter { !" '\u{00A0}\u{202F}".contains($0) }
        let separators = digits.filter { $0 == "." || $0 == "," }
        var normalized = digits
        if Set(separators).count == 2, let last = digits.last(where: { $0 == "." || $0 == "," }) {
            let thousands: Character = last == "." ? "," : "."
            normalized = digits.filter { $0 != thousands }.replacingOccurrences(of: String(last), with: ".")
        } else if let separator = separators.first {
            let parts = digits.split(separator: separator, omittingEmptySubsequences: false)
            let isThousands = separators.count > 1 || parts.last?.count == 3
            normalized = isThousands
                ? digits.filter { $0 != separator }
                : digits.replacingOccurrences(of: String(separator), with: ".")
        }
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Rates relative to EUR, as delivered by open.er-api.com.
struct ExchangeRateTable: Codable, Equatable {
    let rates: [String: Double]
    let fetchedAt: Date
    let nextUpdate: Date

    func convert(_ amount: MoneyAmount, to code: String) -> Double? {
        guard let from = rates[amount.code], let target = rates[code], from > 0 else { return nil }
        return amount.value / from * target
    }

    /// Wire format of `GET https://open.er-api.com/v6/latest/EUR`. Only the
    /// fields Tippi needs; everything else is ignored.
    private struct Response: Decodable {
        let result: String
        let baseCode: String
        let nextUpdateUnix: TimeInterval
        let rates: [String: Double]

        enum CodingKeys: String, CodingKey {
            case result, rates
            case baseCode = "base_code"
            case nextUpdateUnix = "time_next_update_unix"
        }
    }

    static let maxResponseBytes = 256 * 1024

    /// Validates shape and bounds before anything is used — the bytes come
    /// from outside (see the design doc, "Antwort-Parser").
    static func parse(_ data: Data, now: Date) -> ExchangeRateTable? {
        guard data.count <= maxResponseBytes,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.result == "success",
              response.baseCode == "EUR"
        else { return nil }
        let rates = response.rates.filter { code, rate in
            code.count == 3 && code.allSatisfy { $0.isASCII && $0.isUppercase } && rate.isFinite && rate > 0
        }
        guard rates["EUR"] != nil, rates.count >= CurrencyCatalog.codes.count / 2 else { return nil }
        // A next-update time far in the future would freeze the cache; cap it.
        let next = min(Date(timeIntervalSince1970: response.nextUpdateUnix), now.addingTimeInterval(48 * 3600))
        return ExchangeRateTable(rates: rates, fetchedAt: now, nextUpdate: max(next, now))
    }
}

enum CurrencyFormatter {
    static func string(_ value: Double, code: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = code
        return formatter.string(from: NSNumber(value: value)) ?? "\(value) \(code)"
    }

    /// `23 €` → `23 € (≈ 26,19 $)`. Trailing whitespace of the selection (a
    /// double-click often takes the space after the word) stays at the end.
    static func appending(_ converted: Double, code: String, to text: String, locale: Locale = .current) -> String {
        let core = text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        let trailing = String(text.dropFirst(core.count))
        return core + " (≈ " + string(converted, code: code, locale: locale) + ")" + trailing
    }
}

@MainActor
enum CurrencyAction {
    /// The selection with the conversion appended, or `nil` when the text is
    /// no amount or no usable rates exist — then nothing is written.
    static func convertedText(_ text: String, to code: String) async -> String? {
        currencyLog.notice("convert → requested \(code, privacy: .public)")
        // Every exit is logged: the first field test failed without a single
        // trace (2026-09-28). Lengths and codes only — never the text itself.
        guard let amount = CurrencyParser.parse(text) else {
            currencyLog.notice("convert → no amount in selection (\(text.count, privacy: .public) chars)")
            return nil
        }
        guard let table = await ExchangeRateService.shared.rates() else {
            currencyLog.notice("convert → no usable rates")
            return nil
        }
        guard let converted = table.convert(amount, to: code) else {
            currencyLog.notice("convert → no rate for \(amount.code, privacy: .public)→\(code, privacy: .public)")
            return nil
        }
        currencyLog.notice("convert → \(amount.code, privacy: .public)→\(code, privacy: .public) ok")
        return CurrencyFormatter.appending(converted, code: code, to: text)
    }
}

@MainActor
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    static let endpoint = URL(string: "https://open.er-api.com/v6/latest/EUR")!
    static let expectedHost = "open.er-api.com"
    nonisolated static let retryInterval: TimeInterval = 3600
    nonisolated static let rateLimitPause: TimeInterval = 20 * 60
    nonisolated static let maxCacheAge: TimeInterval = 7 * 24 * 3600

    private var table: ExchangeRateTable?
    private var lastAttempt: Date?
    private var blockedUntil: Date?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    private init() {
        table = Self.loadCache()
    }

    enum Decision: Equatable { case useCache, fetch, unavailable }

    /// Pure fetch policy, unit-tested: never more than one request per hour,
    /// a 20-minute pause after HTTP 429, cached rates up to 7 days old.
    nonisolated static func decide(table: ExchangeRateTable?, now: Date,
                                   lastAttempt: Date?, blockedUntil: Date?) -> Decision {
        if let table, now < table.nextUpdate { return .useCache }
        let throttled = (lastAttempt.map { now.timeIntervalSince($0) < retryInterval } ?? false)
            || (blockedUntil.map { now < $0 } ?? false)
        if !throttled { return .fetch }
        if let table, now.timeIntervalSince(table.fetchedAt) <= maxCacheAge { return .useCache }
        return .unavailable
    }

    /// Current rates, fetching only when the policy allows. `nil` means no
    /// usable rates — the caller writes nothing.
    func rates(now: Date = Date()) async -> ExchangeRateTable? {
        let decision = Self.decide(table: table, now: now, lastAttempt: lastAttempt, blockedUntil: blockedUntil)
        currencyLog.notice("rates → \(String(describing: decision), privacy: .public)")
        switch decision {
        case .useCache: return table
        case .unavailable: return nil
        case .fetch: break
        }
        lastAttempt = now
        if let fresh = await fetch(now: now) {
            table = fresh
            Self.saveCache(fresh)
            return fresh
        }
        if let table, now.timeIntervalSince(table.fetchedAt) <= Self.maxCacheAge { return table }
        return nil
    }

    private func fetch(now: Date) async -> ExchangeRateTable? {
        do {
            // Streamed with a byte cap: `data(from:)` would buffer the whole
            // body before any size check could run (rafter-code-review,
            // CWE-400). The real table is ~3 KB.
            let (bytes, response) = try await session.bytes(from: Self.endpoint)
            guard let http = response as? HTTPURLResponse,
                  http.url?.host == Self.expectedHost
            else {
                currencyLog.notice("exchange rates: unexpected response host, discarded")
                return nil
            }
            if http.statusCode == 429 {
                blockedUntil = now.addingTimeInterval(Self.rateLimitPause)
                currencyLog.notice("exchange rates: rate limited (429), pausing 20 min")
                return nil
            }
            guard http.statusCode == 200 else {
                currencyLog.notice("exchange rates: HTTP \(http.statusCode, privacy: .public)")
                return nil
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > ExchangeRateTable.maxResponseBytes {
                    currencyLog.notice("exchange rates: response over size cap, discarded")
                    return nil
                }
            }
            guard let table = ExchangeRateTable.parse(data, now: now) else {
                currencyLog.notice("exchange rates: response failed validation (\(data.count, privacy: .public) bytes)")
                return nil
            }
            currencyLog.notice("exchange rates: fetched \(table.rates.count, privacy: .public) rates")
            return table
        } catch {
            currencyLog.notice("exchange rates: fetch failed (\(error.localizedDescription, privacy: .public))")
            return nil
        }
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tippi", isDirectory: true)
            .appendingPathComponent("exchange-rates.json")
    }

    private static func loadCache() -> ExchangeRateTable? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExchangeRateTable.self, from: data)
    }

    private static func saveCache(_ table: ExchangeRateTable) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(table) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
