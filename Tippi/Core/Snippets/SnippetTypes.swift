import Foundation

/// A single Espanso-style match entry, as parsed from a `matches:` YAML file.
/// Schema is intentionally narrow — only the fields Michael's real match files
/// use (trigger/triggers, replace, vars with type shell|date). Espanso's full
/// spec (word boundaries, forms, images, propagate_case, choice vars, …) is
/// not implemented; add fields here only when a real file actually needs
/// them (Simplicity First) rather than pre-building the whole spec.
/// Decodable only — these are parsed from Espanso YAML for reading, never
/// written back out. Tippi never edits the YAML: importing copies the matches
/// into `ImportedSnippet` and that copy becomes what actually runs, so the file
/// is a one-way input rather than a live source. The custom `init(from:)` below
/// (needed for the trigger/triggers union) would otherwise force a hand-written
/// `encode(to:)` that has no real caller.
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

/// One snippet copied out of an Espanso match file into Tippi's own store —
/// the "import" half of docs/SECURE-DESIGN-espanso-import.md. Unlike
/// `AppSnippet`, `vars` here can legitimately contain a `shell` type, because
/// these came from a file Michael authored outside Tippi, not from the
/// "Insert Variable" picker.
///
/// `shellApproval` is the whole security model in one field: `nil` means "not
/// consented, do not run" and is the only state a shell-bearing snippet can
/// start in, migration or fresh import alike (see the doc's "ask once"
/// section). A non-nil value still has to pass `SnippetApprovalSigner.verify`
/// against the *current* trigger/command before every expansion — storing it
/// here does not itself grant trust, only carries the signed claim.
struct ImportedSnippet: Codable, Equatable, Identifiable {
    let id: UUID
    /// Espanso allows multiple triggers per match; `trigger` (first one) is
    /// what gets signed/verified, `triggers` is what actually gets matched.
    var trigger: String
    var triggers: [String]
    var replace: String
    var vars: [SnippetVar]
    var shellApproval: SnippetApproval?
    /// Path of the Espanso file this came from. Optional because entries
    /// written before this field existed do not carry it.
    ///
    /// Without it, two things were impossible: telling which import a snippet
    /// belongs to (so a file could never be released again once imported —
    /// deleting its snippets left the file invisible in both lists), and
    /// letting two files legitimately define the same trigger, which Espanso
    /// allows and resolves by file precedence.
    var sourcePath: String?

    init(id: UUID = UUID(), triggers: [String], replace: String, vars: [SnippetVar],
         shellApproval: SnippetApproval? = nil, sourcePath: String? = nil) {
        self.id = id
        self.trigger = triggers.first ?? ""
        self.triggers = triggers
        self.replace = replace
        self.vars = vars
        self.shellApproval = shellApproval
        self.sourcePath = sourcePath
    }

    var hasShellVars: Bool { vars.contains { $0.type == "shell" } }

    /// Canonical text of everything that would actually execute, in a form
    /// stable across re-imports of byte-identical content. Fed into
    /// `SnippetApprovalSigner` as the "command" half of the (trigger,
    /// command) pair it signs.
    ///
    /// Each field is length-prefixed, same reasoning as `SnippetApprovalSigner.mac`'s
    /// own length-prefixing of (trigger, command): a plain `"\(name)=\(cmd)"`
    /// join is not collision-resistant when `cmd` may itself contain `=` or
    /// `\n` — two different (name, cmd) pairs could join to the identical
    /// string, letting a store-file edit that changes the actual command
    /// still verify against an old approval's MAC. Sorted by name (not by the
    /// joined string) so sort order can't itself be manipulated by crafting a
    /// name that reorders entries around a collision.
    var shellCommandDigest: String {
        vars.filter { $0.type == "shell" }
            .sorted { $0.name < $1.name }
            .map { shellVar -> String in
                let cmd = shellVar.params.cmd ?? ""
                return "\(shellVar.name.utf8.count):\(shellVar.name)=\(cmd.utf8.count):\(cmd)"
            }
            .joined(separator: "\n")
    }
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
