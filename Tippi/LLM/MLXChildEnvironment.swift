import Foundation

/// Environment for the processes Tippi starts for local MLX (`mlx_lm.server`,
/// `uvx`, and the installer's `brew`/`uv`). Audit 2026-11-17, finding 4.
///
/// macOS attributes a child process to the app that started it, so these
/// processes run with Tippi's Accessibility, Input Monitoring and Microphone
/// grants. Inheriting Tippi's environment let anything that runs as the user
/// inject code into them without an admin password or a TCC prompt:
/// `launchctl setenv PYTHONPATH …` (or `PYTHONSTARTUP`, `DYLD_INSERT_LIBRARIES`
/// — the hardened runtime strips DYLD for Tippi, not for an unsigned Python
/// child) is inherited by every GUI app launched afterwards. Same reasoning
/// and same fix as `SnippetVariableResolver.runShell` (fixed PATH) and the
/// Whisper binary resolution.
///
/// Not closed by this: the MLX install itself lives in user-writable folders
/// (`~/.local/bin`, `~/.local/share/uv`). Whoever can rewrite those files
/// already can; that is the price of a user-space install.
enum MLXChildEnvironment {
    /// Fixed search path: the uv tool folder first (where `uv tool install`
    /// puts `mlx_lm.server`), then Homebrew, then the system.
    static func searchPath(home: String = NSHomeDirectory()) -> String {
        "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    /// Passed through unchanged when set: locale, temp folder, user name and
    /// proxies (the first run downloads the model). Proxies alone cannot read
    /// TLS traffic. Certificate bundles (`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`)
    /// are left out on purpose: together with a proxy they would let an
    /// injected CA intercept `uv tool install mlx-lm` and swap the package.
    /// `UV_*` and `HOMEBREW_*` stay out too (`UV_PYTHON`, `UV_INDEX_URL`
    /// choose what gets executed).
    static let passThrough: Set<String> = [
        "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "no_proxy", "all_proxy",
    ]

    /// Hugging Face settings (`HF_HOME`, `HF_HUB_CACHE`, `HF_TOKEN`, …) only
    /// say where models live and how to fetch them — data, not code.
    static let passThroughPrefixes = ["HF_", "HUGGINGFACE_"]

    static func make(from inherited: [String: String] = ProcessInfo.processInfo.environment,
                     home: String = NSHomeDirectory()) -> [String: String] {
        var env = inherited.filter { key, _ in
            passThrough.contains(key) || passThroughPrefixes.contains { key.hasPrefix($0) }
        }
        env["PATH"] = searchPath(home: home)
        env["HOME"] = home
        return env
    }
}
