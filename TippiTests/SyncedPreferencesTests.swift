import XCTest
@testable import Tippi

/// Covers the settings sync across Macs. The interesting behaviour is not
/// "does a value travel" but "what happens when both sides changed" — that is
/// where a naive implementation loses an edit without saying so.
@MainActor
final class SyncedPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let wordsKey = "dictation.customWords.v1"
    private let stampKey = "dictation.customWords.v1.syncedAt"

    private let suites = ThrowawayDefaults()

    override func setUp() {
        super.setUp()
        defaults = suites.make(prefix: "TippiTests.sync")
        // The real store is a process-wide singleton shared with iCloud; tests
        // drive a stand-in that behaves the same for the parts under test.
        FakeKeyValueStore.shared.reset()
    }

    override func tearDown() {
        // `removePersistentDomain` alone clears the values but leaves the suite
        // registered and its plist on disk — that is why this file leaked 12
        // domains per run despite having a tearDown (measured 2026-09-20).
        suites.removeAll()
        super.tearDown()
    }

    private func makeSync() -> SyncedPreferences {
        SyncedPreferences(store: FakeKeyValueStore.shared.asUbiquitousStore(), defaults: defaults)
    }

    // MARK: - The basic direction

    func testLocalValueIsOfferedToICloud() {
        defaults.set(["CINEWEB", "CineSocial"], forKey: wordsKey)
        let sync = makeSync()
        sync.syncNowForTesting()

        XCTAssertEqual(FakeKeyValueStore.shared.array(forKey: wordsKey) as? [String],
                       ["CINEWEB", "CineSocial"],
                       "a locally edited word list must reach the store")
        XCTAssertGreaterThan(FakeKeyValueStore.shared.double(forKey: stampKey), 0,
                             "a pushed value must carry a timestamp, or the other Mac cannot tell it is newer")
    }

    // MARK: - Conflict handling, the point of the exercise

    func testNewerRemoteValueWins() {
        defaults.set(["alt"], forKey: wordsKey)
        defaults.set(Date().timeIntervalSince1970 - 100, forKey: stampKey)
        FakeKeyValueStore.shared.set(["neu"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(Date().timeIntervalSince1970, forKey: stampKey)

        makeSync().pullNowForTesting()

        XCTAssertEqual(defaults.stringArray(forKey: wordsKey), ["neu"],
                       "the newer side must win")
    }

    func testOlderRemoteValueIsIgnored() {
        let now = Date().timeIntervalSince1970
        defaults.set(["hier-gerade-bearbeitet"], forKey: wordsKey)
        defaults.set(now, forKey: stampKey)
        FakeKeyValueStore.shared.set(["vorgestern"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(now - 3600, forKey: stampKey)

        makeSync().pullNowForTesting()

        XCTAssertEqual(defaults.stringArray(forKey: wordsKey), ["hier-gerade-bearbeitet"],
                       "a stale value from the other Mac must not overwrite a fresher local edit — "
                       + "this is exactly the silent data loss last-write-wins would cause")
    }

    // MARK: - What must never travel

    func testOnlyAllowListedKeysAreSynced() {
        // Hardware-bound and path-bearing settings: pushing these would put a
        // 6 GB model on an 8 GB Mac, or a path from one filesystem on another.
        for forbidden in ["defaultModel.mlx", "defaultProvider", "mlx.port",
                          "tippi.snippets.importedFilePaths.v1"] {
            defaults.set("etwas", forKey: forbidden)
        }
        makeSync().syncNowForTesting()

        for forbidden in ["defaultModel.mlx", "defaultProvider", "mlx.port",
                          "tippi.snippets.importedFilePaths.v1"] {
            XCTAssertNil(FakeKeyValueStore.shared.object(forKey: forbidden),
                         "\(forbidden) must never reach iCloud")
        }
    }

    // MARK: - Oversized values

    func testOversizedValueIsNotSilentlyDropped() {
        // The real store fails writes over its limit without telling anyone.
        // Refusing loudly beats a value that never appears on the other Mac.
        let huge = (0..<20_000).map { "wort-\($0)-mit-etwas-laenge-damit-es-zaehlt" }
        defaults.set(huge, forKey: wordsKey)

        makeSync().syncNowForTesting()

        XCTAssertNil(FakeKeyValueStore.shared.object(forKey: wordsKey),
                     "an oversized value must be refused rather than half-written")
        XCTAssertEqual(defaults.stringArray(forKey: wordsKey)?.count, huge.count,
                       "refusing to sync must not touch the local value")
    }

    // MARK: - No echo

    func testApplyingRemoteValueDoesNotPushItBack() {
        let remoteStamp = Date().timeIntervalSince1970
        FakeKeyValueStore.shared.set(["von-drueben"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(remoteStamp, forKey: stampKey)

        let sync = makeSync()
        sync.pullNowForTesting()
        let stampAfterPull = FakeKeyValueStore.shared.double(forKey: stampKey)

        XCTAssertEqual(stampAfterPull, remoteStamp, accuracy: 0.0001,
                       "applying a remote value must not re-stamp it as a local edit — "
                       + "that would make the two Macs push to each other forever")
    }

    // MARK: - Launch behaviour
    //
    // Reported 2026-09-19: custom words entered on the MacBook never reached the
    // Mac mini. Both Macs were fine, iCloud was fine, the entitlement was fine.
    // Uploading was driven solely by `UserDefaults.didChangeNotification`, so a
    // Mac whose words predated this type simply never sent them — nothing was
    // changing. The data was marooned and looked synced.

    func testWordsThatPredateSyncAreUploadedOnLaunch() {
        // No local timestamp: this Mac has never synced, exactly like one that
        // carried its words across the update to 2.11.0.
        defaults.set(["Dott.Beat", "CINEWEB"], forKey: wordsKey)

        let sync = makeSync()
        sync.startSequenceForTesting()

        XCTAssertEqual(FakeKeyValueStore.shared.array(forKey: wordsKey) as? [String],
                       ["Dott.Beat", "CINEWEB"],
                       "words present before the first launch must be uploaded — "
                       + "waiting for an edit strands them on one Mac")
    }

    func testFirstSyncUnionsBothListsInsteadOfPickingAWinner() {
        // Both Macs hold words from before sync existed, so neither has a local
        // stamp. Without merging, the Mac that starts second loses its list:
        // remoteStamp > localStamp(0) makes the pull overwrite it.
        defaults.set(["Dott.Beat", "CineSocial"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(["CINEWEB", "CineSocial"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(Date().timeIntervalSince1970, forKey: stampKey)

        let sync = makeSync()
        sync.startSequenceForTesting()

        let result = defaults.stringArray(forKey: wordsKey) ?? []
        XCTAssertEqual(Set(result), Set(["Dott.Beat", "CineSocial", "CINEWEB"]),
                       "the first sync must keep both Macs' words — a house spelling "
                       + "added here does not invalidate one added there")
        XCTAssertEqual(result.count, 3, "merging must not duplicate the shared word")
        XCTAssertEqual(FakeKeyValueStore.shared.array(forKey: wordsKey) as? [String] ?? [],
                       result,
                       "the merged list must also be uploaded, or the other Mac never sees it")
    }

    // MARK: - The second synced key
    //
    // Regression 2026-09-19: a blanket `value is [String]` type guard was added
    // to protect the words, and silently blocked every custom prompt —
    // `CustomPromptStore.save()` stores them as JSON `Data`. It shipped in
    // 2.11.1 because every test here only covered the words key. These two
    // cover the other one.

    private let promptsKey = "tippi.customPrompts.v1"
    private let promptsStampKey = "tippi.customPrompts.v1.syncedAt"

    func testCustomPromptsArriveFromICloud() {
        let blob = Data("[{\"title\":\"Kino-Ton\"}]".utf8)
        FakeKeyValueStore.shared.set(blob, forKey: promptsKey)
        FakeKeyValueStore.shared.set(Date().timeIntervalSince1970, forKey: promptsStampKey)

        let sync = makeSync()
        sync.pullNowForTesting()

        XCTAssertEqual(defaults.data(forKey: promptsKey), blob,
                       "custom prompts are stored as JSON Data, not [String] — a type "
                       + "guard written for the words must not drop them")
    }

    func testCustomPromptsAreUploaded() {
        let blob = Data("[{\"title\":\"Kino-Ton\"}]".utf8)
        defaults.set(blob, forKey: promptsKey)

        let sync = makeSync()
        sync.startSequenceForTesting()

        XCTAssertEqual(FakeKeyValueStore.shared.data(forKey: promptsKey), blob,
                       "prompts present before the first launch must be uploaded too")
    }

    func testWrongTypeFromICloudDoesNotWipeTheLocalWords() {
        // A corrupt or future-version store could hold something that is not a
        // string array. Writing it through would make `stringArray(forKey:)`
        // return nil afterwards — the words gone, silently.
        defaults.set(["Dott.Beat"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(["unerwartet": true], forKey: wordsKey)
        FakeKeyValueStore.shared.set(Date().timeIntervalSince1970, forKey: stampKey)

        let sync = makeSync()
        sync.pullNowForTesting()

        XCTAssertEqual(defaults.stringArray(forKey: wordsKey) ?? [], ["Dott.Beat"],
                       "a value of the wrong type must be refused, not written over "
                       + "the words this Mac still has")
    }

    func testLaunchDoesNotOverrideAnAlreadySyncedKey() {
        // This Mac has synced before (it has a stamp) and iCloud holds something
        // newer. Merging would be wrong here — last-write-wins is the contract.
        let localStamp = Date().timeIntervalSince1970 - 100
        let remoteStamp = Date().timeIntervalSince1970
        defaults.set(["alt"], forKey: wordsKey)
        defaults.set(localStamp, forKey: stampKey)
        FakeKeyValueStore.shared.set(["neu"], forKey: wordsKey)
        FakeKeyValueStore.shared.set(remoteStamp, forKey: stampKey)

        let sync = makeSync()
        sync.startSequenceForTesting()

        XCTAssertEqual(defaults.stringArray(forKey: wordsKey) ?? [], ["neu"],
                       "a key that has synced before must follow last-write-wins, not merge")
    }
}

extension SyncedPreferencesTests {
    /// iCloud that swallows every write — what a build without the iCloud
    /// entitlement gets. Pushing then never makes local and remote equal, and the
    /// timestamp write fires `UserDefaults.didChangeNotification`, which pushed
    /// again: unbounded recursion, stack overflow at launch (crash report
    /// 2026-09-24, 56 Tippi frames of `pushLocalChanges` ↔ `start()`).
    func testUnreachableICloudDoesNotRecurse() {
        let sync = SyncedPreferences(store: DeafUbiquitousStore(), defaults: defaults)
        sync.start()
        defer { sync.stopForTesting() }
        defaults.set(["CINEWEB"], forKey: wordsKey)   // must return, not overflow
        XCTAssertEqual(defaults.stringArray(forKey: wordsKey), ["CINEWEB"])
    }
}

final class DeafUbiquitousStore: NSUbiquitousKeyValueStore {
    override func object(forKey aKey: String) -> Any? { nil }
    override func set(_ anObject: Any?, forKey aKey: String) {}
    override func set(_ aDouble: Double, forKey aKey: String) {}
    override func double(forKey aKey: String) -> Double { 0 }
    override func synchronize() -> Bool { false }
}

/// Minimal stand-in for `NSUbiquitousKeyValueStore`.
///
/// `NSUbiquitousKeyValueStore` has no injectable variant, and its `.default`
/// talks to the real iCloud container. This subclass keeps the storage in
/// memory so the conflict rules can be exercised deterministically.
final class FakeKeyValueStore {
    static let shared = FakeKeyValueStore()
    private var storage: [String: Any] = [:]
    private let backing = InMemoryUbiquitousStore()

    func reset() {
        storage.removeAll()
        backing.storage.removeAll()
    }
    func set(_ value: Any, forKey key: String) { backing.storage[key] = value }
    func object(forKey key: String) -> Any? { backing.storage[key] }
    func array(forKey key: String) -> [Any]? { backing.storage[key] as? [Any] }
    /// Custom prompts travel as JSON `Data`, not as a string array — the tests
    /// for that key need to read the value back in its own type.
    func data(forKey key: String) -> Data? { backing.storage[key] as? Data }
    func double(forKey key: String) -> Double { backing.storage[key] as? Double ?? 0 }
    func asUbiquitousStore() -> NSUbiquitousKeyValueStore { backing }
}

final class InMemoryUbiquitousStore: NSUbiquitousKeyValueStore {
    var storage: [String: Any] = [:]
    override func object(forKey aKey: String) -> Any? { storage[aKey] }
    override func set(_ anObject: Any?, forKey aKey: String) { storage[aKey] = anObject }
    override func set(_ aDouble: Double, forKey aKey: String) { storage[aKey] = aDouble }
    override func double(forKey aKey: String) -> Double { storage[aKey] as? Double ?? 0 }
    override func removeObject(forKey aKey: String) { storage.removeValue(forKey: aKey) }
    override func synchronize() -> Bool { true }
}
