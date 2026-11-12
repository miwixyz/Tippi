import Foundation

/// The one thing another app (or a web page) may ask Tippi to do through the
/// `tippi://` URL scheme. Any app can send such a URL, so this is an allowlist,
/// not a parser: exactly `tippi://schnellnotiz` (or with a trailing `/`) is
/// accepted, everything else — query, fragment, user, port, extra path, other
/// host — is refused. Decision and threat model: docs/SECURE-DESIGN-url-schema.md.
enum TippiURLCommand: Equatable {
    /// Opens the quick notes panel under the menu bar icon, like a left click.
    case openQuickNotes

    static let scheme = "tippi"

    static func parse(_ url: URL) -> TippiURLCommand? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme,
              parts.host?.lowercased() == "schnellnotiz",
              parts.query == nil, parts.fragment == nil,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/"
        else { return nil }
        return .openQuickNotes
    }
}
