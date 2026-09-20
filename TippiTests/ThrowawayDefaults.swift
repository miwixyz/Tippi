import Foundation

/// Throwaway `UserDefaults` suites for tests — created on demand, actually
/// removed afterwards.
///
/// Why this exists (measured 2026-09-20): a single `xcodebuild test` run left
/// **35 new preference domains** behind — 23 named `TippiTests.<UUID>` and 12
/// named `TippiTests.sync.<UUID>`. They had accumulated to 636 on one machine.
///
/// The sync ones are the interesting half: `SyncedPreferencesTests` already
/// called `removePersistentDomain(forName:)` in `tearDown` and leaked anyway.
/// That call clears the *values*; it does not unregister the suite, and the
/// backing plist in `~/Library/Preferences` survives. Removing a suite for real
/// takes all three calls below, which is why this is a shared helper rather
/// than a line copied into each test class — the first copy already got it
/// wrong, and two more sites had no cleanup at all.
///
/// No user impact. The cost is that `defaults domains` becomes useless on the
/// development machine, which is where you look when a preference bug is being
/// chased — during the Notes-sync diagnosis on 2026-09-20 the real app domain
/// arrived after 600 lines of test noise. A test run that leaves traces on the
/// machine it runs on is also the same rule that kept a window-creating test
/// out of `SnippetWindowSuppressionTests`.
///
/// Usage:
/// ```swift
/// private let suites = ThrowawayDefaults()
/// override func tearDown() { suites.removeAll(); super.tearDown() }
/// let defaults = suites.make()
/// ```
final class ThrowawayDefaults {
    /// Name **and** the live instance. Holding the instance matters: an earlier
    /// version looked the suite up again with `UserDefaults(suiteName:)` inside
    /// `removeAll()` — which *creates* the suite in order to delete it and left
    /// an empty 42-byte plist behind every time. Measured 2026-09-20: values
    /// gone, 35 empty shells per run, `defaults domains` just as polluted.
    private var suites: [(name: String, defaults: UserDefaults)] = []

    /// Names handed out so far — only for the helper's own tests, which have to
    /// look the plist up on disk to measure removal.
    var debugNames: [String] { suites.map(\.name) }

    /// A fresh, uniquely named suite. `prefix` only affects readability when
    /// inspecting leftovers by hand.
    func make(prefix: String = "TippiTests") -> UserDefaults {
        let name = "\(prefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("UserDefaults(suiteName:) returned nil for \(name)")
        }
        suites.append((name, defaults))
        return defaults
    }

    /// Removes every suite handed out by this instance. Safe to call twice.
    func removeAll() {
        for (name, defaults) in suites {
            // Only the instance already held — never look the suite up again,
            // see the comment on `suites`.
            defaults.removePersistentDomain(forName: name)
            defaults.removeSuite(named: name)
            UserDefaults.standard.removeSuite(named: name)
            // `removePersistentDomain` empties the domain; the (now empty) plist
            // in ~/Library/Preferences survives and still shows up in
            // `defaults domains`. Removing the file is the only thing that
            // actually clears it, and a throwaway test suite is exactly the case
            // where that is correct rather than reckless.
            let plist = FileManager.default
                .urls(for: .libraryDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Preferences/\(name).plist")
            if let plist { try? FileManager.default.removeItem(at: plist) }
        }
        suites.removeAll()
    }

    deinit {
        // A test class that forgets `removeAll()` still does not leak. The
        // explicit call in `tearDown` stays, because ARC gives no guarantee
        // about *when* this runs.
        removeAll()
    }
}
