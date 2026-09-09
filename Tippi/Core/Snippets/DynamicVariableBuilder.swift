import Foundation

/// Generates a `SnippetVar` from one of a fixed, curated set of templates —
/// the "idiot-proof" alternative to hand-typing a `date -v ...` shell
/// command. The user picks a weekday from a menu and a number from a
/// stepper; they never see or write shell syntax. Because every generated
/// command comes from these templates (fixed structure, numeric/enum
/// parameters only — never free text interpolated into a shell string),
/// app-created dynamic snippets skip the file-approval gate that imported
/// Espanso files go through: there's no externally-authored command here to
/// review, Tippi wrote all of it from a reviewed template.
enum DynamicVariableKind: Equatable {
    case today(format: DateFormatPreset)
    case weekday(Weekday, extraDays: Int, format: DateFormatPreset)
    /// Fixed pattern matching the already-proven-working command from
    /// Michael's own kinowoche.yml (`date -v +thu +"%V"`) — ISO week number
    /// anchored to the week's Thursday, not "whatever weekday today happens
    /// to be" (which would misreport near week boundaries).
    case calendarWeek
}

enum DateFormatPreset: CaseIterable, Equatable {
    case dayDot
    case dayMonth
    case dayMonthYear
    case year

    /// strftime tokens — identical to what `SnippetVariableResolver` already
    /// feeds to the real `strftime()` call, so these presets are exactly the
    /// formats already proven to work in Michael's real match files.
    var strftimeFormat: String {
        switch self {
        case .dayDot: return "%d."
        case .dayMonth: return "%d. %B"
        case .dayMonthYear: return "%d. %B %Y"
        case .year: return "%Y"
        }
    }

    var displayName: String {
        switch self {
        case .dayDot: return String(localized: "settings.snippets.variable.format.dayDot")
        case .dayMonth: return String(localized: "settings.snippets.variable.format.dayMonth")
        case .dayMonthYear: return String(localized: "settings.snippets.variable.format.dayMonthYear")
        case .year: return String(localized: "settings.snippets.variable.format.year")
        }
    }
}

enum Weekday: CaseIterable, Equatable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    /// BSD `date -v` weekday flags (`+mon`, `+tue`, …) — always English
    /// three-letter abbreviations regardless of system locale, matching
    /// what the real kinowoche.yml already uses (`-v +thu`).
    var dateFlag: String {
        switch self {
        case .monday: return "mon"
        case .tuesday: return "tue"
        case .wednesday: return "wed"
        case .thursday: return "thu"
        case .friday: return "fri"
        case .saturday: return "sat"
        case .sunday: return "sun"
        }
    }

    var displayName: String {
        switch self {
        case .monday: return String(localized: "settings.snippets.variable.weekday.monday")
        case .tuesday: return String(localized: "settings.snippets.variable.weekday.tuesday")
        case .wednesday: return String(localized: "settings.snippets.variable.weekday.wednesday")
        case .thursday: return String(localized: "settings.snippets.variable.weekday.thursday")
        case .friday: return String(localized: "settings.snippets.variable.weekday.friday")
        case .saturday: return String(localized: "settings.snippets.variable.weekday.saturday")
        case .sunday: return String(localized: "settings.snippets.variable.weekday.sunday")
        }
    }
}

enum DynamicVariableBuilder {
    static func makeVar(name: String, kind: DynamicVariableKind) -> SnippetVar {
        switch kind {
        case .today(let format):
            return SnippetVar(name: name, type: "date", params: SnippetVarParams(cmd: nil, format: format.strftimeFormat))

        case .weekday(let weekday, let extraDays, let format):
            var cmd = "date -v +\(weekday.dateFlag)"
            if extraDays != 0 {
                let sign = extraDays > 0 ? "+" : "-"
                cmd += " -v \(sign)\(abs(extraDays))d"
            }
            cmd += " +\"\(format.strftimeFormat)\""
            return SnippetVar(name: name, type: "shell", params: SnippetVarParams(cmd: cmd, format: nil))

        case .calendarWeek:
            return SnippetVar(name: name, type: "shell", params: SnippetVarParams(cmd: "date -v +thu +\"%V\"", format: nil))
        }
    }
}
