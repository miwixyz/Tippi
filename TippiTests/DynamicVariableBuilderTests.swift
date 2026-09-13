import XCTest
@testable import Tippi

final class DynamicVariableBuilderTests: XCTestCase {
    /// `.today` is routed through the shell with an explicit `LC_TIME`
    /// prefix, same as `.weekday` — NOT the direct-`strftime()` `type: "date"`
    /// path, which has no locale override and silently renders month names
    /// in whatever locale the process inherits. Real bug found in a second
    /// code-review pass, 2026-09-13, after the identical bug had already been
    /// fixed once for `.weekday`.
    func testTodayGeneratesLCTimeShellCommand() {
        let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .today(format: .dayMonthYear))
        XCTAssertEqual(variable.type, "shell")
        XCTAssertEqual(variable.params.cmd, "LC_TIME=de_DE.UTF-8 date +\"%d. %B %Y\"")
        XCTAssertNil(variable.params.format)
    }

    func testWeekdayWithoutExtraDaysGeneratesPlainDateVCommand() {
        let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .weekday(.thursday, extraDays: 0, format: .dayDot))
        XCTAssertEqual(variable.type, "shell")
        XCTAssertEqual(variable.params.cmd, "LC_TIME=de_DE.UTF-8 date -v +thu +\"%d.\"")
    }

    /// Must match the exact real-world command from Michael's kinowoche.yml
    /// (`:nl-mi` = Donnerstag + 6 Tage) — this is the whole point of the
    /// picker: producing exactly the command an Espanso power user would
    /// have hand-written, without them typing it. This test previously
    /// expected a command *without* `LC_TIME=de_DE.UTF-8` while claiming to
    /// match the real file — the real file always had that prefix. Verified
    /// against a real date (2026-09-13): without it, `%B` rendered "June",
    /// not "Juni" — a real, silent bug in already-shipped code, not just a
    /// stale test expectation.
    func testWeekdayWithPositiveExtraDaysMatchesRealKinowocheCommand() {
        let variable = DynamicVariableBuilder.makeVar(name: "wed", kind: .weekday(.thursday, extraDays: 6, format: .dayMonth))
        XCTAssertEqual(variable.params.cmd, "LC_TIME=de_DE.UTF-8 date -v +thu -v +6d +\"%d. %B\"")
    }

    func testWeekdayWithNegativeExtraDays() {
        let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .weekday(.monday, extraDays: -3, format: .year))
        XCTAssertEqual(variable.params.cmd, "LC_TIME=de_DE.UTF-8 date -v +mon -v -3d +\"%Y\"")
    }

    /// The whole reason for always prefixing, even for locale-independent
    /// formats like `.dayDot`/`.year`: relying on the format to decide
    /// whether the prefix is "needed" is exactly the kind of per-case
    /// reasoning that let the missing-prefix bug ship in the first place.
    func testLCTimePrefixPresentForEveryWeekdayFormatNotJustMonthNames() {
        for format in DateFormatPreset.allCases {
            let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .weekday(.friday, extraDays: 0, format: format))
            XCTAssertTrue(variable.params.cmd?.hasPrefix("LC_TIME=de_DE.UTF-8 ") ?? false,
                           "\(format) is missing the locale prefix: \(variable.params.cmd ?? "nil")")
        }
    }

    func testCalendarWeekMatchesRealKinowocheCommand() {
        let variable = DynamicVariableBuilder.makeVar(name: "kw", kind: .calendarWeek)
        XCTAssertEqual(variable.params.cmd, "date -v +thu +\"%V\"")
    }

    /// End-to-end: the generated var actually resolves via the real shell
    /// resolver, not just producing plausible-looking text.
    func testGeneratedWeekdayVariableActuallyResolves() {
        let variable = DynamicVariableBuilder.makeVar(name: "wd", kind: .weekday(.thursday, extraDays: 0, format: .year))
        let match = SnippetMatch(triggers: [":test"], replace: "{{wd}}", vars: [variable])
        let result = SnippetVariableResolver.resolve(match)
        XCTAssertEqual(result.count, 4)
        XCTAssertNotNil(Int(result))
    }

    func testAllWeekdaysProduceDistinctDateFlags() {
        let flags = Set(Weekday.allCases.map(\.dateFlag))
        XCTAssertEqual(flags.count, Weekday.allCases.count, "each weekday must map to a unique date -v flag")
    }
}
