import XCTest
@testable import Tippi

final class DynamicVariableBuilderTests: XCTestCase {
    func testTodayGeneratesDateTypeWithFormat() {
        let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .today(format: .dayMonthYear))
        XCTAssertEqual(variable.type, "date")
        XCTAssertEqual(variable.params.format, "%d. %B %Y")
        XCTAssertNil(variable.params.cmd)
    }

    func testWeekdayWithoutExtraDaysGeneratesPlainDateVCommand() {
        let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .weekday(.thursday, extraDays: 0, format: .dayDot))
        XCTAssertEqual(variable.type, "shell")
        XCTAssertEqual(variable.params.cmd, "date -v +thu +\"%d.\"")
    }

    /// Must match the exact real-world command from Michael's kinowoche.yml
    /// (`:nl-mi` = Donnerstag + 6 Tage) — this is the whole point of the
    /// picker: producing exactly the command an Espanso power user would
    /// have hand-written, without them typing it.
    func testWeekdayWithPositiveExtraDaysMatchesRealKinowocheCommand() {
        let variable = DynamicVariableBuilder.makeVar(name: "wed", kind: .weekday(.thursday, extraDays: 6, format: .dayMonth))
        XCTAssertEqual(variable.params.cmd, "date -v +thu -v +6d +\"%d. %B\"")
    }

    func testWeekdayWithNegativeExtraDays() {
        let variable = DynamicVariableBuilder.makeVar(name: "v1", kind: .weekday(.monday, extraDays: -3, format: .year))
        XCTAssertEqual(variable.params.cmd, "date -v +mon -v -3d +\"%Y\"")
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
