import XCTest
@testable import Tippi

final class EspansoYAMLParserTests: XCTestCase {
    func testParsesSimpleStaticMatch() throws {
        let yaml = """
        matches:
          - trigger: ":espanso"
            replace: "Hi there!"
        """
        let file = try EspansoYAMLParser.parse(yaml)
        XCTAssertEqual(file.matches.count, 1)
        XCTAssertEqual(file.matches[0].triggers, [":espanso"])
        XCTAssertEqual(file.matches[0].replace, "Hi there!")
        XCTAssertTrue(file.matches[0].vars.isEmpty)
    }

    func testParsesShellVar() throws {
        let yaml = """
        matches:
          - trigger: ":shell"
            replace: "{{output}}"
            vars:
              - name: output
                type: shell
                params:
                  cmd: "echo 'Hello from your shell'"
        """
        let file = try EspansoYAMLParser.parse(yaml)
        let variable = file.matches[0].vars[0]
        XCTAssertEqual(variable.name, "output")
        XCTAssertEqual(variable.type, "shell")
        XCTAssertEqual(variable.params.cmd, "echo 'Hello from your shell'")
    }

    func testParsesDateVar() throws {
        let yaml = """
        matches:
          - trigger: ":date"
            replace: "{{mydate}}"
            vars:
              - name: mydate
                type: date
                params:
                  format: "%m/%d/%Y"
        """
        let file = try EspansoYAMLParser.parse(yaml)
        let variable = file.matches[0].vars[0]
        XCTAssertEqual(variable.type, "date")
        XCTAssertEqual(variable.params.format, "%m/%d/%Y")
    }

    func testParsesMultilineBlockScalarReplace() throws {
        let yaml = """
        matches:
          - trigger: ":mlg"
            replace: |-
              Liebe Grüße
              Michael
        """
        let file = try EspansoYAMLParser.parse(yaml)
        XCTAssertEqual(file.matches[0].replace, "Liebe Grüße\nMichael")
    }

    /// The exact file Michael pasted as the feature request — a regression
    /// guard on this specific real-world file, not just a synthetic example.
    func testParsesRealKinowocheFile() throws {
        let yaml = """
        matches:
          - trigger: ":nl"
            replace: "Kinowoche vom {{thu}} bis {{wed}} {{year}}"
            vars:
              - name: thu
                type: shell
                params:
                  cmd: 'date -v +thu +"%d."'
              - name: wed
                type: shell
                params:
                  cmd: 'LC_TIME=de_DE.UTF-8 date -v +thu -v +6d +"%d. %B"'
              - name: year
                type: shell
                params:
                  cmd: 'date +"%Y"'

          - trigger: ":nl-do"
            replace: "{{thu}}"
            vars:
              - name: thu
                type: shell
                params:
                  cmd: 'LC_TIME=de_DE.UTF-8 date -v +thu +"%d. %B %Y"'

          - trigger: ":nl-mi"
            replace: "{{wed}}"
            vars:
              - name: wed
                type: shell
                params:
                  cmd: 'LC_TIME=de_DE.UTF-8 date -v +thu -v +6d +"%d. %B %Y"'

          - trigger: ":nl-nr"
            replace: "KW {{kw}}"
            vars:
              - name: kw
                type: shell
                params:
                  cmd: 'date -v +thu +"%V"'
        """
        let file = try EspansoYAMLParser.parse(yaml)
        XCTAssertEqual(file.matches.count, 4)
        XCTAssertEqual(file.matches.map { $0.triggers[0] }, [":nl", ":nl-do", ":nl-mi", ":nl-nr"])
        XCTAssertEqual(file.matches[0].vars.count, 3)
        XCTAssertEqual(file.matches[0].vars[1].params.cmd, "LC_TIME=de_DE.UTF-8 date -v +thu -v +6d +\"%d. %B\"")
    }

    func testThrowsOnMalformedYAML() {
        let yaml = "matches: [this is not: valid: - yaml structure"
        XCTAssertThrowsError(try EspansoYAMLParser.parse(yaml))
    }
}
