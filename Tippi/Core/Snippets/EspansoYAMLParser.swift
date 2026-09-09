import Foundation
import Yams

/// Parses real Espanso match files (`~/Library/Application Support/espanso/match/*.yml`)
/// so Tippi can read them as-is — no reformatting, no migration step. A
/// malformed file must never take down every other loaded file, so parsing
/// is per-file and errors are the caller's problem to log-and-skip
/// (see `SnippetStore.reloadEspansoFiles`).
enum EspansoYAMLParser {
    static func parse(_ yamlString: String) throws -> EspansoMatchFile {
        try YAMLDecoder().decode(EspansoMatchFile.self, from: yamlString)
    }

    static func parseFile(at url: URL) throws -> EspansoMatchFile {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parse(contents)
    }
}
