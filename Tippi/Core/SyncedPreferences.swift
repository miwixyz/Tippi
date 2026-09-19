import Foundation
import os

private let syncLog = Logger(subsystem: "com.tippi.app", category: "sync")

/// Carries a hand-picked set of settings across the user's Macs via
/// `NSUbiquitousKeyValueStore`.
///
/// ## What is synced, and what deliberately is not
///
/// Only settings that mean the same thing on every machine. The list is
/// explicit rather than "everything except", because the dangerous direction
/// is adding a key by accident, not forgetting one:
///
/// - **Custom words** — a house spelling is a property of the user's writing,
///   not of a machine.
/// - **Custom prompts** — same reasoning.
///
/// Excluded on purpose, each for a concrete reason:
///
/// - **API keys** live in the Keychain and stay there. Apple already syncs the
///   Keychain through iCloud Keychain, which is the channel built for secrets;
///   this store is plain and would hold them in the clear.
/// - **The signing key for shell approvals** is `ThisDeviceOnly` and must stay
///   that way. If it travelled, approving a command on one Mac would authorise
///   it everywhere — including from a machine that has been compromised.
///   Synced shell snippets therefore arrive unverifiable on the second Mac and
///   ask for consent again. That is the intended behaviour, not a gap.
/// - **Local model choice and MLX port** are hardware-bound. Michael's two Macs
///   differ in memory; syncing the choice would push a model onto the smaller
///   machine where it is the wrong answer, not the same one.
/// - **Anything holding a path** (watched snippet directory, imported file
///   paths) — a path is a statement about one filesystem.
///
/// ## Conflict handling
///
/// `NSUbiquitousKeyValueStore` resolves conflicts per key as last-write-wins,
/// which silently discards one side's edit. Each synced key therefore carries a
/// timestamp, and an incoming value is only applied when it is genuinely newer
/// than what this Mac last saw. Simultaneous edits on two Macs still resolve to
/// one winner — that is inherent — but the common case (edit here, open the
/// other Mac tomorrow) never loses anything.
@MainActor
final class SyncedPreferences {
    static let shared = SyncedPreferences()

    /// Hard ceiling documented by Apple for the whole store. Exceeding it makes
    /// writes fail **silently**, so a value is checked before it is offered
    /// rather than discovered missing on the other Mac.
    private static let valueSizeLimit = 64 * 1024

    /// The allow-list. Adding a key here is a deliberate act; see the type
    /// documentation for what does not belong.
    private static let syncedKeys = [
        "dictation.customWords.v1",
        "tippi.customPrompts.v1",
    ]

    private let store: NSUbiquitousKeyValueStore
    private let defaults: UserDefaults
    /// Guards against the echo: applying a remote value writes to UserDefaults,
    /// which fires the change notification, which would push it straight back.
    private var isApplyingRemote = false
    private var observers: [NSObjectProtocol] = []

    init(store: NSUbiquitousKeyValueStore = .default, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    private static func timestampKey(for key: String) -> String { "\(key).syncedAt" }

    // MARK: - Lifecycle

    /// Starts syncing. Safe to call once at launch.
    func start() {
        let external = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.applyRemoteChanges(note) }
        }
        let local = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushLocalChanges() }
        }
        observers = [external, local]

        // `synchronize` only asks for an upload of pending local changes; the
        // download arrives via the notification above. Pulling explicitly here
        // covers the first launch on a new Mac, where no notification fires
        // because nothing changed while this process was running.
        //
        // The push side needs the same treatment, and for a long time it did
        // not have it: a Mac that already held custom words before this type
        // existed never uploaded them, because uploading was driven purely by
        // `UserDefaults.didChangeNotification` and nothing was changing. The
        // words sat there looking synced and reached no other Mac. Reported
        // 2026-09-19 with exactly that symptom.
        store.synchronize()
        reconcileFirstSync()
        applyRemoteChanges(nil)
        pushLocalChanges()
    }

    /// Merges instead of letting one Mac silently win the first time a key syncs.
    ///
    /// Both Macs may hold words from before this type existed, and neither has
    /// a local timestamp then. `applyRemoteChanges` compares `remoteStamp >
    /// localStamp` and a missing local stamp reads as `0` — so whichever Mac
    /// starts second would have its own list replaced by the other's, with no
    /// warning and no way back. Custom words are additive by nature: a house
    /// spelling added here does not invalidate one added there. So on the very
    /// first sync of a key, the two lists are unioned and the result is stamped
    /// `now`, which is newer than the remote stamp and therefore survives the
    /// pull that follows.
    ///
    /// Only string arrays are merged. Anything else falls through to the normal
    /// last-write-wins path, because merging is only obviously correct for a set.
    private func reconcileFirstSync() {
        for key in Self.syncedKeys {
            // A stamp means this Mac has synced the key before; last-write-wins
            // is then the right and expected behaviour.
            guard defaults.double(forKey: Self.timestampKey(for: key)) == 0 else { continue }
            guard let local = defaults.stringArray(forKey: key), !local.isEmpty else { continue }
            guard let remote = store.object(forKey: key) as? [String], !remote.isEmpty else { continue }
            guard local != remote else { continue }

            var merged = local
            for value in remote where !merged.contains(value) { merged.append(value) }

            let now = Date().timeIntervalSince1970
            isApplyingRemote = true
            defaults.set(merged, forKey: key)
            defaults.set(now, forKey: Self.timestampKey(for: key))
            isApplyingRemote = false
            syncLog.info("first sync for \(key, privacy: .public): merged \(local.count) local + \(remote.count) remote into \(merged.count)")
        }
    }

    // MARK: - Directions

    /// Applies values that are newer than what this Mac last recorded.
    private func applyRemoteChanges(_ note: Notification?) {
        // A changed-key list is present for real external changes and absent on
        // the initial pull, where every key is a candidate.
        let changed = note?.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        let candidates = changed.map { keys in Self.syncedKeys.filter { keys.contains($0) } }
            ?? Self.syncedKeys

        for key in candidates {
            let remoteStamp = store.double(forKey: Self.timestampKey(for: key))
            guard remoteStamp > 0 else { continue }
            let localStamp = defaults.double(forKey: Self.timestampKey(for: key))
            guard remoteStamp > localStamp else { continue }
            guard let value = store.object(forKey: key) else { continue }

            // Both synced keys are string arrays. Writing anything else into
            // UserDefaults would make `stringArray(forKey:)` return nil on the
            // next read — the words would be gone locally with nothing logged
            // and no way to tell it apart from "never had any". A wrong type
            // means a corrupt or future-version store, so refuse and say so
            // rather than destroy what this Mac still holds.
            guard value is [String] else {
                syncLog.error("iCloud holds a \(type(of: value), privacy: .public) for \(key, privacy: .public), expected [String] — keeping the local value")
                continue
            }

            isApplyingRemote = true
            defaults.set(value, forKey: key)
            defaults.set(remoteStamp, forKey: Self.timestampKey(for: key))
            isApplyingRemote = false
            syncLog.info("applied newer value for \(key, privacy: .public) from iCloud")
        }
    }

    /// Offers local values whose content differs from what iCloud holds.
    ///
    /// Compares content rather than tracking "dirty" state: `UserDefaults`
    /// change notifications fire for every key in the domain, most of which are
    /// none of this type's business.
    private func pushLocalChanges() {
        guard !isApplyingRemote else { return }

        for key in Self.syncedKeys {
            guard let local = defaults.object(forKey: key) else { continue }
            let remote = store.object(forKey: key)
            guard !equal(local, remote) else { continue }

            guard let size = encodedSize(of: local) else {
                syncLog.error("cannot size value for \(key, privacy: .public) — not syncing it")
                continue
            }
            guard size <= Self.valueSizeLimit else {
                // Silence here would be the worst outcome: the value would
                // simply never appear on the other Mac, with nothing to see.
                syncLog.error("\(key, privacy: .public) is \(size) bytes, over the \(Self.valueSizeLimit)-byte sync limit — keeping it local")
                continue
            }

            let now = Date().timeIntervalSince1970
            store.set(local, forKey: key)
            store.set(now, forKey: Self.timestampKey(for: key))
            defaults.set(now, forKey: Self.timestampKey(for: key))
            syncLog.info("pushed \(key, privacy: .public) to iCloud")
        }
    }

    // MARK: - Helpers

    /// Property-list values compare correctly through `NSObject.isEqual`;
    /// `as? AnyHashable` would fail for arrays and dictionaries.
    private func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l as NSObject, r as NSObject): return l.isEqual(r)
        default: return false
        }
    }

    private func encodedSize(of value: Any) -> Int? {
        try? PropertyListSerialization.data(
            fromPropertyList: value, format: .binary, options: 0
        ).count
    }

    // MARK: - Testing seam

    /// Exposed for tests: runs one round trip without the notification plumbing.
    func syncNowForTesting() {
        pushLocalChanges()
        applyRemoteChanges(nil)
    }

    /// Exposed for tests: the exact sequence `start()` runs, minus the observer
    /// registration. Kept in lockstep with `start()` — the launch path is where
    /// the 2026-09-19 data-marooning bug lived, so it needs its own coverage.
    func startSequenceForTesting() {
        reconcileFirstSync()
        applyRemoteChanges(nil)
        pushLocalChanges()
    }

    /// Exposed for tests: applies whatever iCloud holds, ignoring notifications.
    func pullNowForTesting() {
        applyRemoteChanges(nil)
    }
}
