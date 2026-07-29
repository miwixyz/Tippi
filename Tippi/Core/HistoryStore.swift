import Foundation
import CryptoKit
import GRDB
import Security

/// On-disk SQLite store for the AI transformation history.
///
/// **Storage layout.** The database file lives at
/// `~/Library/Application Support/Tippi/history.db`. Tippi has no app sandbox
/// (required for cross-app text capture) so the path is shared with the rest
/// of the user's data; macOS FileVault provides the at-rest file-system
/// encryption.
///
/// **Field-level encryption.** The two content-bearing columns — `input_sealed`
/// and `output_sealed` — are AES-GCM ciphertext blobs produced by CryptoKit.
/// Every other column (`timestamp`, `app_name`, `prompt_title`, `provider`,
/// `model`, `language`, `latency_ms`) is plaintext so the list view and any
/// future filters can query without a Crypto round-trip. The 256-bit key is
/// generated lazily on first write and stored in the macOS Keychain under
/// `com.tippi.app` / `history.encryption.key`, with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and no iCloud sync.
///
/// **Opt-in.** `isEnabled` defaults to `false`; `append(...)` is a no-op until
/// the user toggles History on in Settings.
final class HistoryStore: @unchecked Sendable {

    /// Shared instance. Crashes only if Application Support is unwritable —
    /// at that point the rest of Tippi is broken anyway.
    static let shared: HistoryStore = {
        do { return try HistoryStore() }
        catch { fatalError("HistoryStore failed to initialize: \(error)") }
    }()

    private let dbQueue: DatabaseQueue
    private let enabledDefaultsKey = "historyEnabled"

    // MARK: - User preference

    /// Whether the user has activated History recording. Persisted in UserDefaults.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
    }

    // MARK: - Init

    init() throws {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Tippi", isDirectory: true)
        try FileManager.default.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true
        )
        let dbURL = supportDir.appendingPathComponent("history.db")

        var config = Configuration()
        config.label = "Tippi.HistoryStore"
        self.dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        try Self.migrator.migrate(dbQueue)
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull()
                t.column("app_name", .text).notNull()
                t.column("prompt_title", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text)
                t.column("language", .text)
                t.column("latency_ms", .integer).notNull()
                t.column("input_sealed", .blob).notNull()
                t.column("output_sealed", .blob).notNull()
            }
            try db.create(
                index: "idx_history_timestamp",
                on: "history",
                columns: ["timestamp"]
            )
        }
        return migrator
    }

    // MARK: - CRUD

    /// Inserts a new entry. No-ops when `isEnabled == false`.
    /// Returns the new row id, or `nil` if recording is disabled.
    @discardableResult
    func append(
        appName: String,
        promptTitle: String,
        provider: String,
        model: String?,
        language: String?,
        latencyMs: Int,
        input: String,
        output: String,
        timestamp: Date = Date()
    ) throws -> Int64? {
        guard isEnabled else { return nil }

        let key = try Self.encryptionKey()
        let inputSealed = try Self.seal(input, key: key)
        let outputSealed = try Self.seal(output, key: key)

        return try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO history (
                    timestamp, app_name, prompt_title, provider, model,
                    language, latency_ms, input_sealed, output_sealed
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    timestamp.timeIntervalSince1970,
                    appName,
                    promptTitle,
                    provider,
                    model,
                    language,
                    latencyMs,
                    inputSealed,
                    outputSealed
                ])
            return db.lastInsertedRowID
        }
    }

    /// Fetches entries newest-first.
    func fetch(limit: Int = 100, offset: Int = 0) throws -> [HistoryEntry] {
        let key = try Self.encryptionKey()
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, timestamp, app_name, prompt_title, provider, model,
                       language, latency_ms, input_sealed, output_sealed
                FROM history
                ORDER BY timestamp DESC
                LIMIT ? OFFSET ?
                """, arguments: [limit, offset])
            return try rows.map { try Self.decode(row: $0, key: key) }
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history") ?? 0
        }
    }

    func delete(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM history WHERE id = ?", arguments: [id])
        }
    }

    /// Removes every row. The encryption key is preserved — use `purge()` for a full reset.
    func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM history")
        }
        // VACUUM cannot run inside a transaction — SQLite rejects it with error 1
        // ("cannot VACUUM from within a transaction"), which would roll back the
        // DELETE above. Reclaim space in a separate, transaction-free write and
        // treat compaction failure as non-fatal (the rows are already gone).
        do {
            try dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "VACUUM")
            }
        } catch {
            NSLog("Tippi: history VACUUM after deleteAll failed (non-fatal): \(error.localizedDescription)")
        }
    }

    /// Removes every row AND drops the Keychain key. The next write generates a fresh key.
    func purge() throws {
        try deleteAll()
        try Self.deleteEncryptionKey()
    }

    // MARK: - Export

    /// JSON array of decrypted entries, newest first, pretty-printed with sorted keys.
    func exportJSON() throws -> Data {
        let iso = ISO8601DateFormatter()
        let entries = try fetch(limit: Int.max)
        let payload: [[String: Any]] = entries.map { e in
            var dict: [String: Any] = [
                "timestamp": iso.string(from: e.timestamp),
                "app": e.appName,
                "prompt": e.promptTitle,
                "provider": e.provider,
                "latency_ms": e.latencyMs,
                "input": e.input,
                "output": e.output
            ]
            if let model = e.model { dict["model"] = model }
            if let language = e.language { dict["language"] = language }
            return dict
        }
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// CSV (header + rows). Fields containing commas, quotes, or newlines are RFC-4180 escaped.
    func exportCSV() throws -> Data {
        let iso = ISO8601DateFormatter()
        let entries = try fetch(limit: Int.max)
        var csv = "timestamp,app,prompt,provider,model,language,latency_ms,input,output\n"
        for e in entries {
            let cols: [String] = [
                iso.string(from: e.timestamp),
                e.appName,
                e.promptTitle,
                e.provider,
                e.model ?? "",
                e.language ?? "",
                String(e.latencyMs),
                e.input,
                e.output
            ]
            csv += cols.map(Self.csvEscape).joined(separator: ",") + "\n"
        }
        return Data(csv.utf8)
    }

    private static func csvEscape(_ s: String) -> String {
        // Neutralize spreadsheet formula injection: input/output contain
        // LLM/captured text, and Excel/Numbers execute fields starting with
        // these characters as formulas when the CSV is opened.
        var s = s
        if let first = s.first, "=+-@".contains(first) {
            s = "'" + s
        }
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    // MARK: - Row decoding

    private static func decode(row: Row, key: SymmetricKey) throws -> HistoryEntry {
        let inputSealed: Data = row["input_sealed"]
        let outputSealed: Data = row["output_sealed"]
        let timestamp: Double = row["timestamp"]
        return HistoryEntry(
            id: row["id"],
            timestamp: Date(timeIntervalSince1970: timestamp),
            appName: row["app_name"],
            promptTitle: row["prompt_title"],
            provider: row["provider"],
            model: row["model"],
            language: row["language"],
            latencyMs: row["latency_ms"],
            input: try open(inputSealed, key: key),
            output: try open(outputSealed, key: key)
        )
    }

    // MARK: - AES-GCM

    private static func seal(_ plaintext: String, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = box.combined else { throw HistoryStoreError.sealFailed }
        return combined
    }

    private static func open(_ sealed: Data, key: SymmetricKey) throws -> String {
        let box = try AES.GCM.SealedBox(combined: sealed)
        let data = try AES.GCM.open(box, using: key)
        guard let s = String(data: data, encoding: .utf8) else {
            throw HistoryStoreError.decryptUTF8Failed
        }
        return s
    }

    // MARK: - Keychain-backed encryption key

    private static let keychainService = "com.tippi.app"
    private static let keychainAccount = "history.encryption.key"

    private static func encryptionKey() throws -> SymmetricKey {
        if let data = try fetchKeyData() {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try storeKeyData(raw)
        return key
    }

    private static func deleteEncryptionKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HistoryStoreError.keychainStatus(status)
        }
    }

    private static func fetchKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw HistoryStoreError.keychainStatus(status)
        }
        guard let data = item as? Data else {
            throw HistoryStoreError.unexpectedKeychainData
        }
        return data
    }

    private static func storeKeyData(_ data: Data) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw HistoryStoreError.keychainStatus(addStatus)
            }
        default:
            throw HistoryStoreError.keychainStatus(updateStatus)
        }
    }
}

enum HistoryStoreError: LocalizedError {
    case sealFailed
    case decryptUTF8Failed
    case keychainStatus(OSStatus)
    case unexpectedKeychainData

    var errorDescription: String? {
        switch self {
        case .sealFailed:
            return "Failed to encrypt history entry."
        case .decryptUTF8Failed:
            return "Failed to decode a decrypted history entry."
        case .keychainStatus(let status):
            return "Keychain error (\(status))."
        case .unexpectedKeychainData:
            return "Keychain returned unexpected data."
        }
    }
}
