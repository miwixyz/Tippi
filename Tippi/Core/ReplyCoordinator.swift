import AppKit
import Foundation
import os

private let replyLog = Logger(subsystem: "com.tippi.app", category: "reply")

/// Ablauf von „Antwort per Sprache": Kontext holen, lokales Modell fragen, Vorschau
/// zeigen, nach Klick einfügen. Design: `docs/SECURE-DESIGN-antwort.md`.
@MainActor
final class ReplyCoordinator {
    static let shared = ReplyCoordinator()

    private let window = ReplyPreviewWindowController()
    private var generation: Task<Void, Never>?

    var isOpen: Bool { window.isOpen }

    /// Zeigt die Vorschau und gibt `true` zurück. `false`: nicht zuständig — der
    /// Aufrufer fügt das Diktat wie gewohnt ein (es geht nie etwas verloren).
    func begin(intent: String, targetApp: NSRunningApplication?,
               targetField: FocusedFieldReader.FocusSpot?) async -> Bool {
        let bundleID = targetApp?.bundleIdentifier
        guard ReplySettings.isEnabled,
              !ReplyLogic.isBlocked(bundleID: bundleID, excluded: AutocompleteSettings.excludedBundleIDs) else {
            return false
        }
        guard await Self.ownLocalServerReady() else {
            replyLog.notice("reply skipped: no own local MLX server")
            ToastWindowController.shared.show(message: String(localized: "reply.toast.needsLocalModel"), seconds: 4)
            return false
        }
        let context = ReplyContextReader.read(app: targetApp)
        let model = ReplyDraftModel(
            intent: intent,
            context: ReplyLogic.trimContext(context.text),
            contextSource: context.source,
            notice: context.notice,
            appName: targetApp?.localizedName ?? "",
            bundleID: bundleID,
            isMail: ReplyLogic.isMail(bundleID: bundleID, context: context.text),
            formal: ReplyLogic.isFormal(context: context.text),
            language: ReplyLogic.language(context: context.text, intent: intent)
        )
        window.show(model: model,
                    onInsert: { [weak self] text in self?.insert(text, into: targetApp, targetField: targetField) },
                    onRegenerate: { [weak self] in self?.generate(model) },
                    onPickRegion: { [weak self] in self?.pickRegion(model) },
                    onCancel: { [weak self] in self?.generation?.cancel() })
        generate(model)
        return true
    }

    /// Nur ein Server, den Tippi selbst gestartet hat (Design §3 „Spoofing") —
    /// kein Cloud-Anbieter, kein Apple Intelligence, kein übernommener Port.
    static func ownLocalServerReady() async -> Bool {
        guard MLXServerManager.isInstalled else { return false }
        do { _ = try await MLXServerManager.shared.start() } catch { return false }
        return MLXServerManager.shared.ownedServerURL != nil
    }

    private func generate(_ model: ReplyDraftModel) {
        generation?.cancel()
        model.phase = .loading
        let system = ReplyLogic.systemPrompt(name: ReplySettings.signOffName)
        let user = ReplyLogic.userText(appName: model.appName, isMail: model.isMail, context: model.context,
                                       intent: model.intent, language: model.language)
        let started = Date()
        generation = Task {
            do {
                // Zweites Schloss direkt vor dem Senden: der Server könnte inzwischen
                // gewechselt haben.
                guard await Self.ownLocalServerReady() else { throw ReplyError.noLocalModel }
                let output = try await MLXProvider().complete(systemPrompt: system, userText: user,
                                                              model: MLXServerManager.activeModel, temperature: 0.3)
                try Task.checkCancellation()
                var text = ReplyLogic.sanitize(output)
                guard !text.isEmpty else { throw ReplyError.empty }
                if model.isMail {
                    text = ReplyLogic.appendSignOff(text, name: ReplySettings.signOffName, formal: model.formal,
                                                    language: model.language)
                }
                model.text = text
                model.hasPlaceholder = ReplyLogic.hasPlaceholder(text)
                model.phase = .ready
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                replyLog.notice("reply drafted chars=\(text.count, privacy: .public) ms=\(ms, privacy: .public) mail=\(model.isMail, privacy: .public) lang=\(model.language.rawValue, privacy: .public) context=\(model.contextSource.rawValue, privacy: .public)")
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                model.phase = .failed(error.localizedDescription)
                replyLog.error("reply failed — \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// „Bereich wählen“: Vorschau weg, Rahmen um die Nachricht ziehen, mit dem erkannten
    /// Text neu schreiben. Abbruch lässt den bisherigen Kontext stehen.
    private func pickRegion(_ model: ReplyDraftModel) {
        generation?.cancel()
        window.setHidden(true)
        Task { @MainActor in
            let text = await AppDelegate.shared?.pickScreenText()
            window.setHidden(false)
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if model.phase == .loading { generate(model) }
                return
            }
            model.context = ReplyLogic.trimContext(text)
            model.contextSource = .region
            model.notice = nil
            model.isMail = ReplyLogic.isMail(bundleID: model.bundleID, context: text)
            model.formal = ReplyLogic.isFormal(context: text)
            let language = ReplyLogic.language(context: text, intent: model.intent)
            replyLog.notice("reply context source=region chars=\(text.count, privacy: .public)")
            if model.language != language {
                model.language = language   // löst über die Vorschau selbst „neu schreiben“ aus
            } else {
                generate(model)
            }
        }
    }

    private func insert(_ text: String, into targetApp: NSRunningApplication?,
                        targetField: FocusedFieldReader.FocusSpot?) {
        generation?.cancel()
        Task { @MainActor in
            let outcome = await DictationController.insert(text, correction: nil, into: targetApp,
                                                           targetField: targetField, fit: false)
            ToastWindowController.shared.show(message: outcome.notice ?? String(localized: "reply.toast.inserted"))
        }
    }
}

enum ReplyError: LocalizedError {
    case noLocalModel, empty

    var errorDescription: String? {
        switch self {
        case .noLocalModel: return String(localized: "reply.toast.needsLocalModel")
        case .empty: return String(localized: "reply.error.empty")
        }
    }
}

/// Zustand der Vorschau. Der Text ist editierbar, bevor er eingefügt wird.
@MainActor
final class ReplyDraftModel: ObservableObject {
    enum Phase: Equatable {
        case loading, ready
        case failed(String)
    }

    let intent: String
    let appName: String
    let bundleID: String?
    @Published var context: String
    @Published var contextSource: ReplyContextReader.Source
    @Published var notice: String?
    @Published var isMail: Bool
    var formal: Bool

    @Published var language: ReplyLanguage
    @Published var text = ""
    @Published var phase: Phase = .loading
    @Published var hasPlaceholder = false

    init(intent: String, context: String, contextSource: ReplyContextReader.Source, notice: String?,
         appName: String, bundleID: String?, isMail: Bool, formal: Bool, language: ReplyLanguage) {
        self.intent = intent
        self.bundleID = bundleID
        self.context = context
        self.contextSource = contextSource
        self.notice = notice
        self.appName = appName
        self.isMail = isMail
        self.formal = formal
        self.language = language
    }
}
