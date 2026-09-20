import AppKit
import UserNotifications
import os

private let notifyLog = Logger(subsystem: "com.tippi.app", category: "problem-notifier")

/// Tells the user, unprompted, that Tippi has stopped working — and what to do.
///
/// Why this exists (2026-09-20, reported): the menubar showed a red dot and the
/// word "Fehler". The actual cause — a stalled model download — was written
/// into a settings pane nobody had open, and nothing announced it. Michael only
/// found out because he happened to look. *"Pop-Up kommt keines!"*
///
/// Design constraints, in the order they mattered:
///
/// - **A notification must carry the instruction, not just the symptom.** The
///   vault rule for automated messages is explicit: what is going on, plus a
///   concrete next step or an explicit "nothing to do". Title says what broke,
///   body says what to do.
/// - **It must not nag.** The status monitor recomputes every 3 s; posting on
///   every tick would be unusable. Only a *transition* into a problem notifies,
///   and the same problem never notifies twice in a row.
/// - **A denied permission must not swallow the message.** If notifications are
///   off, the menu still carries everything — that path is the durable one, the
///   notification is the announcement. Nothing is silently lost either way,
///   which is the failure mode this whole change is about.
@MainActor
final class ProblemNotifier {
    static let shared = ProblemNotifier()
    private init() {}

    /// The last problem announced, so a 3-second poll cannot repeat itself.
    private var lastAnnounced: TippiStatusMonitor.Problem?
    /// `nil` until the system has answered once.
    private var authorizationGranted: Bool?

    /// Call on every status change. Posts only on entering a *new* problem.
    func statusChanged(to status: TippiStatusMonitor.Status) {
        if let problem = decide(status) { post(problem) }
    }

    /// The whole "when do we bother the user" rule, separated from the posting
    /// so it can be tested without a notification centre. It mutates
    /// `lastAnnounced`, which is the point — the rule *is* the state machine.
    ///
    /// Returns the problem to announce, or `nil` for stay quiet.
    func decide(_ status: TippiStatusMonitor.Status) -> TippiStatusMonitor.Problem? {
        guard let problem = status.problem else {
            // Recovered — clear, so the next occurrence announces again rather
            // than being swallowed as a repeat.
            lastAnnounced = nil
            return nil
        }
        guard problem != lastAnnounced else { return nil }
        lastAnnounced = problem
        return problem
    }

    /// Test seam only: forget what was announced.
    func resetForTesting() { lastAnnounced = nil }

    private func post(_ problem: TippiStatusMonitor.Problem) {
        // Authorization FIRST, then deliver — not both at once.
        //
        // Posting while the permission sheet is still up drops the notification
        // silently, so the very first problem a user ever hits would announce
        // itself into nothing. That is the exact failure this class exists to
        // remove, reproduced one layer down.
        authorize { granted in
            guard granted else { return }   // menu still carries everything
            // `Task { @MainActor in }`, NOT `MainActor.assumeIsolated`.
            //
            // This closure runs on UNUserNotificationCenter's own dispatch
            // queue (`UNUserNotificationServiceConnection.call-out`), never on
            // the main actor. `assumeIsolated` does not check-and-adapt — it
            // *asserts*, and a false assertion is a hard trap. Shipped in
            // 2.11.5 and crashed Tippi on launch for anyone who had a problem
            // to report, which is precisely the audience this class is for.
            Task { @MainActor in ProblemNotifier.shared.deliver(problem) }
        }
    }

    fileprivate func deliver(_ problem: TippiStatusMonitor.Problem) {
        let content = UNMutableNotificationContent()
        content.title = problem.headline
        content.body = problem.action
        content.sound = nil   // a writing assistant going quiet is not an alarm

        let request = UNNotificationRequest(
            identifier: "tippi.problem.\(UUID().uuidString)",
            content: content,
            trigger: nil   // deliver now
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                // Never silent: if the announcement itself fails, that is
                // exactly the class of failure being fixed here.
                notifyLog.error("notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Asks once, remembers the answer, and always calls back — including when
    /// permission was already decided in an earlier session.
    private func authorize(_ completion: @escaping (Bool) -> Void) {
        if let known = authorizationGranted {
            completion(known)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                notifyLog.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                notifyLog.notice("notifications not permitted — the menubar menu remains the full report")
            }
            Task { @MainActor in ProblemNotifier.shared.authorizationGranted = granted }
            completion(granted)
        }
    }
}
