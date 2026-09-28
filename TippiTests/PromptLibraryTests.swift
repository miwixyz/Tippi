import XCTest
@testable import Tippi

/// Editable built-ins + one shared order across built-in and custom prompts.
/// Every store here runs on a throwaway suite — the test host is the installed
/// app, `.standard` is the user's real prompt list (CONTRIBUTING.md).
@MainActor
final class PromptLibraryTests: XCTestCase {
    private let suites = ThrowawayDefaults()
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = suites.make()
        FakeKeyValueStore.shared.reset()
    }

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func prompt(_ id: String, title: String? = nil) -> DemoPrompt {
        DemoPrompt(id: id, title: title ?? id, symbol: "star", systemPrompt: "do \(id)", transform: { $0 })
    }

    private func ids(_ prompts: [DemoPrompt]) -> [String] { prompts.map(\.id) }

    // MARK: - Order

    func testEmptyOrderKeepsTodaysOrder() {
        let custom = CustomPrompt(title: "Eigen", symbol: "", systemPrompt: "x")
        let result = DemoPrompt.ordered(builtIn: [prompt("a"), prompt("b")], custom: [custom], edits: [:], order: [])
        XCTAssertEqual(ids(result), ["a", "b", custom.demoID],
                       "without a stored order: built-ins first, then custom — no change for existing users")
    }

    func testUnknownPromptsAreAppendedInDefaultOrder() {
        // "c" is a built-in a later version adds, "d" a custom prompt created after the last reorder.
        let result = PromptOrderStore.apply(["b", "a"], to: [prompt("a"), prompt("b"), prompt("c"), prompt("d")])
        XCTAssertEqual(ids(result), ["b", "a", "c", "d"])
    }

    func testVanishedAndDuplicateIDsAreIgnored() {
        let result = PromptOrderStore.apply(["gone", "b", "b", "a"], to: [prompt("a"), prompt("b")])
        XCTAssertEqual(ids(result), ["b", "a"])
    }

    func testCustomPromptCanMoveAmongBuiltIns() {
        let custom = CustomPrompt(title: "Eigen", symbol: "", systemPrompt: "x")
        let result = DemoPrompt.ordered(builtIn: [prompt("a"), prompt("b")], custom: [custom],
                                        edits: [:], order: [custom.demoID, "b"])
        XCTAssertEqual(ids(result), [custom.demoID, "b", "a"])
    }

    func testMoveStoresTheWholeVisibleOrder() {
        let store = PromptOrderStore(defaults: defaults)
        store.move(["a", "b", "c"], fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.order, ["c", "a", "b"])
        XCTAssertEqual(defaults.stringArray(forKey: PromptOrderStore.storageKey), ["c", "a", "b"])
        XCTAssertEqual(PromptOrderStore(defaults: defaults).order, ["c", "a", "b"], "must survive a relaunch")
    }

    func testDigitKeysFollowTheOrderedList() {
        // The popup gives digits 1–9 to the first nine entries of the list it is
        // handed (PromptPopupView); `all` is that list. A custom prompt moved to
        // the top therefore gets "1" — before this change it never got a digit.
        let builtIns = (1...12).map { prompt("b\($0)") }
        let custom = CustomPrompt(title: "Eigen", symbol: "", systemPrompt: "x")
        let result = DemoPrompt.ordered(builtIn: builtIns, custom: [custom], edits: [:], order: [custom.demoID])
        XCTAssertEqual(result.first?.id, custom.demoID)
        XCTAssertEqual(ids(Array(result.prefix(9))), [custom.demoID] + (1...8).map { "b\($0)" })
    }

    // MARK: - Edits to built-ins

    func testUneditedBuiltInKeepsItsLocalizedTitle() throws {
        let original = try XCTUnwrap(DemoPrompt.builtIn.first { $0.id == "improve" })
        let result = DemoPrompt.ordered(builtIn: DemoPrompt.builtIn, custom: [], edits: [:], order: [])
        XCTAssertEqual(result.first { $0.id == "improve" }?.title, String(localized: "prompt.improve"))
        XCTAssertEqual(result.first { $0.id == "improve" }?.systemPrompt, original.systemPrompt)
    }

    func testEditOnlyStoresWhatChanged() throws {
        let original = try XCTUnwrap(DemoPrompt.builtIn.first { $0.id == "improve" })
        let edit = BuiltInPromptEdit(original: original, title: original.title, symbol: original.symbol,
                                     systemPrompt: "Mach es besser.", pipeline: nil)
        XCTAssertNil(edit.title, "an unchanged title must stay localized, not be frozen in one language")
        XCTAssertNil(edit.symbol)
        XCTAssertEqual(edit.systemPrompt, "Mach es besser.")

        let unchanged = BuiltInPromptEdit(original: original, title: original.title, symbol: original.symbol,
                                          systemPrompt: original.instructions, pipeline: nil)
        XCTAssertTrue(unchanged.isEmpty, "saving without changes must not mark the prompt as edited")
    }

    func testEditIsAppliedAndResetRestoresTheOriginal() throws {
        let original = try XCTUnwrap(DemoPrompt.builtIn.first { $0.id == "improve" })
        let store = BuiltInPromptEditStore(defaults: defaults)
        store.set(BuiltInPromptEdit(title: "Glätten", symbol: "star", systemPrompt: "Mach es glatt."), for: "improve")

        let edited = try XCTUnwrap(DemoPrompt.ordered(builtIn: DemoPrompt.builtIn, custom: [], edits: store.edits, order: [])
            .first { $0.id == "improve" })
        XCTAssertEqual(edited.title, "Glätten")
        XCTAssertEqual(edited.symbol, "star")
        XCTAssertTrue(edited.systemPrompt.hasSuffix("Mach es glatt."))
        XCTAssertTrue(BuiltInPromptEditStore(defaults: defaults).isEdited("improve"), "must survive a relaunch")

        store.reset(id: "improve")
        XCTAssertFalse(store.isEdited("improve"))
        let restored = DemoPrompt.ordered(builtIn: DemoPrompt.builtIn, custom: [], edits: store.edits, order: [])
            .first { $0.id == "improve" }
        XCTAssertEqual(restored?.title, original.title)
        XCTAssertEqual(restored?.systemPrompt, original.systemPrompt)
        XCTAssertNotNil(defaults.data(forKey: BuiltInPromptEditStore.storageKey),
                        "a reset must be written, not removed — SyncedPreferences only pushes keys that exist")
    }

    func testChainStaysAChain() throws {
        let chain = try XCTUnwrap(DemoPrompt.builtIn.first { $0.id == "chainCleanupEN" })
        let edited = chain.applying(BuiltInPromptEdit(title: "Aufräumen → EN", pipeline: ["fixGrammar", "translateDE"]))
        XCTAssertTrue(edited.isChain)
        XCTAssertEqual(edited.pipeline, ["fixGrammar", "translateDE"])
        XCTAssertEqual(edited.id, "chainCleanupEN", "the id is what chains, overrides and migrations reference")

        let single = try XCTUnwrap(DemoPrompt.builtIn.first { $0.id == "shorten" })
        XCTAssertFalse(single.applying(BuiltInPromptEdit(pipeline: ["a", "b"])).isChain,
                       "a single-step built-in must not turn into a chain")
    }

    // MARK: - Custom prompts: injectable store, backwards compatibility

    func testStoredCustomPromptsFromBeforeThisChangeStillLoad() throws {
        // Exact shape an older version wrote: no `pipeline` key at all.
        let uuid = UUID()
        let json = "[{\"id\":\"\(uuid.uuidString)\",\"title\":\"Kino-Ton\",\"symbol\":\"film\",\"systemPrompt\":\"Schreib wie ein Kino.\"}]"
        defaults.set(Data(json.utf8), forKey: CustomPromptStore.storageKey)

        let store = CustomPromptStore(defaults: defaults)
        XCTAssertEqual(store.prompts.count, 1)
        XCTAssertEqual(store.prompts.first?.title, "Kino-Ton")
        XCTAssertEqual(store.prompts.first?.demoID, "custom-\(uuid.uuidString)")
        XCTAssertNil(store.prompts.first?.pipeline)
    }

    func testCustomPromptStoreWritesOnlyToItsInjectedDefaults() {
        let store = CustomPromptStore(defaults: defaults)
        store.add(CustomPrompt(title: "Neu", symbol: "", systemPrompt: "x"))
        XCTAssertNotNil(defaults.data(forKey: CustomPromptStore.storageKey))
        XCTAssertEqual(CustomPromptStore(defaults: defaults).prompts.map(\.title), ["Neu"])
    }

    // MARK: - Sync: both new keys must be in syncedKeys AND hasExpectedType

    private func makeSync() -> SyncedPreferences {
        SyncedPreferences(store: FakeKeyValueStore.shared.asUbiquitousStore(), defaults: defaults)
    }

    func testPromptOrderIsUploadedAndAccepted() {
        // Upload proves `syncedKeys`, acceptance proves `hasExpectedType` —
        // a key missing from either one does not sync, silently.
        PromptOrderStore(defaults: defaults).move(["a", "b"], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        makeSync().syncNowForTesting()
        XCTAssertEqual(FakeKeyValueStore.shared.array(forKey: PromptOrderStore.storageKey) as? [String], ["b", "a"])

        let other = suites.make()
        SyncedPreferences(store: FakeKeyValueStore.shared.asUbiquitousStore(), defaults: other).pullNowForTesting()
        XCTAssertEqual(other.stringArray(forKey: PromptOrderStore.storageKey), ["b", "a"])
    }

    func testBuiltInEditsAreUploadedAndAccepted() {
        BuiltInPromptEditStore(defaults: defaults).set(BuiltInPromptEdit(title: "Glätten"), for: "improve")
        let blob = defaults.data(forKey: BuiltInPromptEditStore.storageKey)
        makeSync().syncNowForTesting()
        XCTAssertEqual(FakeKeyValueStore.shared.data(forKey: BuiltInPromptEditStore.storageKey), blob)

        let other = suites.make()
        SyncedPreferences(store: FakeKeyValueStore.shared.asUbiquitousStore(), defaults: other).pullNowForTesting()
        XCTAssertEqual(BuiltInPromptEditStore(defaults: other).edits["improve"]?.title, "Glätten")
    }
}
