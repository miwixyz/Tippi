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
        walk.measure = DictationSettings.store.bool(forKey: measureKey)
        walk.buttonValues = buttonValueApps.contains(app.bundleIdentifier ?? "")
        // Die Chatliste links gehört nicht zum Kontext (Gerätetest 19.11.: Vorschauen anderer
        // Chats im Kontext). Gelesen wird nur, was rechts über die linke Kante des
        // Eingabefelds hinausreicht — also die Spalte des offenen Chats.
        if walk.buttonValues, let focused,
           let origin = FocusedFieldReader.point(focused, kAXPositionAttribute as String) {
            walk.columnMinX = origin.x
        }
        walk.collect(window, depth: 0)
        if walk.measure { logMeasurement(walk, app: app) }
        if walk.columnMinX != nil {
            replyContextLog.notice("reply context column filter skipped=\(walk.skippedOutsideColumn, privacy: .public)")
        }
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

    /// Messpunkt (Gerätetest WhatsApp 19.11.: nur 83 Zeichen gelesen). Ein mit
    /// `defaults write com.tippi.app dictation.reply.measure -bool true`: protokolliert je
    /// Rolle, welche Attribute Text tragen (Anzahl + Zeichen) und welche Attributnamen
    /// vorkommen — nur Namen und Zahlen, nie Inhalt.
    static let measureKey = "dictation.reply.measure"
    static let buttonValueApps: Set<String> = ["net.whatsapp.WhatsApp"]
    static let measuredAttributes = [kAXValueAttribute as String, kAXTitleAttribute as String,
                                     kAXDescriptionAttribute as String, kAXHelpAttribute as String]

    private static func logMeasurement(_ walk: Walk, app: NSRunningApplication) {
        let text = walk.textStats.sorted { $0.value.chars > $1.value.chars }.prefix(25)
            .map { "\($0.key)=\($0.value.count)/\($0.value.chars)" }.joined(separator: " ")
        let names = walk.attributeNames.sorted { $0.value > $1.value }.prefix(40)
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let id = app.bundleIdentifier ?? "?"
        replyContextLog.notice("reply measure app=\(id, privacy: .public) text[role.attr=count/chars]: \(text, privacy: .public)")
        replyContextLog.notice("reply measure app=\(id, privacy: .public) attrs[name=nodes]: \(names, privacy: .public)")
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
        var measure = false
        /// Nur für Apps, deren Nachrichten Knöpfe sind — sonst landen Schalterwerte im Kontext.
        var buttonValues = false
        /// Linke Kante des Eingabefelds; Text, der ganz links davon endet, wird übergangen.
        var columnMinX: CGFloat?
        var skippedOutsideColumn = 0

        private func isLeftOfColumn(_ element: AXUIElement) -> Bool {
            guard let columnMinX,
                  let origin = FocusedFieldReader.point(element, kAXPositionAttribute as String) else { return false }
            var ref: CFTypeRef?
            var size = CGSize.zero
            guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success,
                  let raw = ref, CFGetTypeID(raw) == AXValueGetTypeID(),
                  // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
                  AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return false }
            return origin.x + size.width <= columnMinX
        }
        var textStats: [String: (count: Int, chars: Int)] = [:]
        var attributeNames: [String: Int] = [:]

        init(deadline: CFAbsoluteTime) { self.deadline = deadline }

        /// Catalyst-Apps (WhatsApp, gemessen 19.11.) legen Text in `AXDescription` statt
        /// `AXValue`, Nachrichtenblasen sind Knöpfe mit dem Text als `AXValue`.
        private func text(of element: AXUIElement, role: String) -> String? {
            if textRoles.contains(role) {
                let value = FocusedFieldReader.string(element, kAXValueAttribute as String)
                if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
                guard role == kAXStaticTextRole as String else { return nil }
                return FocusedFieldReader.string(element, kAXDescriptionAttribute as String)
            }
            guard buttonValues, role == kAXButtonRole as String else { return nil }
            return FocusedFieldReader.string(element, kAXValueAttribute as String)
        }

        private mutating func record(_ element: AXUIElement) {
            let role = FocusedFieldReader.string(element, kAXRoleAttribute as String) ?? "?"
            for attr in measuredAttributes {
                guard let value = FocusedFieldReader.string(element, attr),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let key = "\(role).\(attr)"
                let old = textStats[key] ?? (0, 0)
                textStats[key] = (old.count + 1, old.chars + value.count)
            }
            var namesRef: CFArray?
            if AXUIElementCopyAttributeNames(element, &namesRef) == .success, let names = namesRef as? [String] {
                for name in names { attributeNames[name, default: 0] += 1 }
            }
        }

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
            if measure { record(element) }
            if let role = FocusedFieldReader.string(element, kAXRoleAttribute as String),
               let value = text(of: element, role: role) {
                let trimmed = value.replacingOccurrences(of: "\u{200E}", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, isLeftOfColumn(element) {
                    skippedOutsideColumn += 1
                } else if !trimmed.isEmpty, trimmed != parts.last {
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
