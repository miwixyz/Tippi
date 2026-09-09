import Foundation

/// A single Espanso-style match entry, as parsed from a `matches:` YAML file.
/// Schema is intentionally narrow — only the fields Michael's real match files
/// use (trigger/triggers, replace, vars with type shell|date). Espanso's full
/// spec (word boundaries, forms, images, propagate_case, choice vars, …) is
/// not implemented; add fields here only when a real file actually needs
/// them (Simplicity First) rather than pre-building the whole spec.
/// Decodable only — these are parsed from Espanso YAML for reading, never
/// written back out (the file itself stays the source of truth), and the
/// custom `init(from:)` below (needed for the trigger/triggers union) would
/// otherwise force a hand-written `encode(to:)` that has no real caller.
struct SnippetMatch: Decodable, Equatable {
    /// Espanso supports both `trigger: "..."` and `triggers: ["...", "..."]`.
    /// Decoded into a single array internally so callers don't care which
    /// form a given file used.
    let triggers: [String]
    let replace: String
    let vars: [SnippetVar]

    private enum CodingKeys: String, CodingKey {
        case trigger, triggers, replace, vars
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let multi = try c.decodeIfPresent([String].self, forKey: .triggers) {
            triggers = multi
        } else {
            triggers = [try c.decode(String.self, forKey: .trigger)]
        }
        replace = try c.decode(String.self, forKey: .replace)
        vars = try c.decodeIfPresent([SnippetVar].self, forKey: .vars) ?? []
    }

    init(triggers: [String], replace: String, vars: [SnippetVar] = []) {
        self.triggers = triggers
        self.replace = replace
        self.vars = vars
    }
}

struct SnippetVar: Codable, Equatable {
    let name: String
    /// "shell" | "date" — the only two types any real match file uses.
    /// Anything else is a recognized-but-unsupported type, resolved to an
    /// empty string at expansion time rather than failing the whole file's
    /// parse (see `SnippetVariableResolver`).
    let type: String
    let params: SnippetVarParams
}

struct SnippetVarParams: Codable, Equatable {
    /// For `type: shell` — a full shell command line (not an argv array),
    /// matching Espanso's own semantics. Real files rely on that shape:
    /// `LC_TIME=de_DE.UTF-8 date -v +thu -v +6d +"%d. %B"`.
    let cmd: String?
    /// For `type: date` — a strftime-style format string, e.g. "%m/%d/%Y".
    let format: String?
}

/// Top-level shape of an Espanso match YAML file (`matches: [...]`).
struct EspansoMatchFile: Decodable, Equatable {
    let matches: [SnippetMatch]
}

/// A snippet created directly in Tippi's UI — trigger → text, optionally with
/// dynamic `vars` (date/weekday variables inserted via the "Insert Variable"
/// picker in the editor, never hand-typed shell). `vars` empty = the plain
/// static case. Unlike Espanso files, these vars are always Tippi-generated
/// from a fixed set of templates (see `DynamicVariableBuilder`) — never
/// arbitrary user-typed shell — so they don't go through the file-approval
/// gate; there's nothing external to approve.
struct AppSnippet: Codable, Equatable, Identifiable {
    let id: UUID
    var trigger: String
    var replacement: String
    var vars: [SnippetVar]

    private enum CodingKeys: String, CodingKey {
        case id, trigger, replacement, vars
    }

    init(id: UUID = UUID(), trigger: String, replacement: String, vars: [SnippetVar] = []) {
        self.id = id
        self.trigger = trigger
        self.replacement = replacement
        self.vars = vars
    }

    // Custom init so snippets saved before `vars` existed still decode
    // (missing key → empty array) instead of failing to load at all.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        trigger = try c.decode(String.self, forKey: .trigger)
        replacement = try c.decode(String.self, forKey: .replacement)
        vars = try c.decodeIfPresent([SnippetVar].self, forKey: .vars) ?? []
    }
}
