import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

private let replyContextLog = Logger(subsystem: "com.tippi.app", category: "reply-context")

/// Holt die Nachricht, auf die „Antwort per Sprache" antwortet: zuerst die
/// Markierung, sonst den sichtbaren Text des vordersten Fensters über die
/// Bedienungshilfen. Nur auf Auslösung, nie im Hintergrund, nie ins Protokoll
/// (geloggt werden Quelle, Zeichenzahl, Knoten, Dauer und App — kein Text).
/// Design §3 „Fremde App → Tippi" in `docs/SECURE-DESIGN-antwort.md`.
@MainActor
enum ReplyContextReader {
    enum Source: String {
        case selection, window, none
    }

    struct Context {
        let text: String
        let source: Source
        /// Grund, warum kein Kontext gelesen wurde (für den Hinweis in der Vorschau).
        let notice: String?

        static func empty(_ notice: String? = nil) -> Context { Context(text: "", source: .none, notice: notice) }
    }

    /// Ganzer Baumdurchlauf, nicht je Aufruf — sonst friert ein breites Fenster Tippi ein
    /// (gleiche Begründung wie `TextCapture.axWalkBudget`).
    static let walkBudget: CFTimeInterval = 0.5
    static let maxNodes = 4000
    /// Mehr wird nicht gesammelt; ans Modell gehen davon höchstens die letzten 3.000 Zeichen.
    static let maxCollectedCharacters = 60_000
    /// Webseiten (Gmail in Helium) schachteln tief. Tiefer wird nur dieser Zweig
    /// übersprungen, der Rest des Fensters wird weiter gelesen (Gerätetest 19.11.:
    /// Abbruch bei Tiefe 30 nach 648 Knoten, Mailtext fehlte).
    static let maxDepth = 80
    static let textRoles: Set<String> = [kAXStaticTextRole as String, kAXTextAreaRole as String,
                                         kAXTextFieldRole as String]

    static func read(app: NSRunningApplication?) -> Context {
        guard let app, AXIsProcessTrusted() else { return .empty() }
        // Ein Passwortfeld irgendwo im System hat die sichere Eingabe an: dann nichts lesen.
        if IsSecureEventInputEnabled() {
            replyContextLog.notice("reply context skipped: secure input active")
            return .empty(String(localized: "reply.context.secureInput"))
        }
        let started = CFAbsoluteTimeGetCurrent()
        let focused = FocusedFieldReader.focusedElement(pid: app.processIdentifier)
        if let focused, FocusedFieldReader.isSecure(focused) {
            return .empty(String(localized: "reply.context.secureInput"))
        }
        if let focused, let selected = TextCapture.selectedText(from: focused),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log(.selection, chars: selected.count, nodes: 0, started: started, app: app)
            return Context(text: selected, source: .selection, notice: nil)
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = FocusedFieldReader.element(appElement, kAXFocusedWindowAttribute as String) else {
            return .empty()
        }
        var walk = Walk(deadline: started + walkBudget)
        walk.collect(window, depth: 0)
        let text = walk.parts.joined(separator: "\n")
        log(.window, chars: text.count, nodes: walk.nodes, started: started, app: app, truncated: walk.truncated,
            stopped: walk.stopped)
        return text.isEmpty ? .empty() : Context(text: text, source: .window, notice: nil)
    }

    private static func log(_ source: Source, chars: Int, nodes: Int, started: CFAbsoluteTime,
                            app: NSRunningApplication, truncated: Bool = false, stopped: Bool = false) {
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        replyContextLog.notice("reply context source=\(source.rawValue, privacy: .public) chars=\(chars, privacy: .public) nodes=\(nodes, privacy: .public) ms=\(ms, privacy: .public) truncated=\(truncated, privacy: .public) stopped=\(stopped, privacy: .public) app=\(app.bundleIdentifier ?? "?", privacy: .public)")
    }

    /// Text der Textelemente in Dokumentreihenfolge, begrenzt nach Zeit, Knoten und Länge.
    @MainActor
    private struct Walk {
        let deadline: CFAbsoluteTime
        var parts: [String] = []
        var nodes = 0
        var characters = 0
        /// Etwas wurde ausgelassen (zu tief oder Budget erschöpft) — fürs Protokoll.
        var truncated = false
        /// Budget erschöpft: ganzen Durchlauf beenden.
        var stopped = false

        init(deadline: CFAbsoluteTime) { self.deadline = deadline }

        mutating func collect(_ element: AXUIElement, depth: Int) {
            guard !stopped else { return }
            guard nodes < maxNodes, characters < maxCollectedCharacters,
                  CFAbsoluteTimeGetCurrent() < deadline else {
                stopped = true
                truncated = true
                return
            }
            guard depth <= maxDepth else {
                truncated = true
                return
            }
            nodes += 1
            if FocusedFieldReader.isSecure(element) { return }
            if let role = FocusedFieldReader.string(element, kAXRoleAttribute as String), textRoles.contains(role),
               let value = FocusedFieldReader.string(element, kAXValueAttribute as String) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != parts.last {
                    parts.append(trimmed)
                    characters += trimmed.count
                }
            }
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else { return }
            for child in children {
                collect(child, depth: depth + 1)
                if stopped { return }
            }
        }
    }
}
