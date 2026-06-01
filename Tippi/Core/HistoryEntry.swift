import Foundation

/// A single AI text-transformation, decrypted, ready for UI display or export.
///
/// On disk the `input` and `output` strings live as AES-GCM ciphertext blobs;
/// everything else (timestamp, app name, prompt title, provider) is plaintext
/// so the list view and filters do not need to round-trip through CryptoKit.
struct HistoryEntry: Identifiable, Hashable {
    /// SQLite rowid. Always present — `HistoryEntry` instances are only produced
    /// by `HistoryStore.fetch(...)`, never constructed in-memory before insert
    /// (the insert path uses individual parameters on `HistoryStore.append`).
    let id: Int64

    let timestamp: Date

    /// User-facing name of the app where the transformation was triggered (e.g. "Mail", "Safari").
    let appName: String

    /// Title of the prompt the user picked from the popup (built-in or custom).
    let promptTitle: String

    /// Provider id (e.g. "openai", "anthropic", "mlx", "ollama").
    let provider: String

    /// Concrete model the provider used for this call (e.g. "gpt-4o-mini"). Optional
    /// because local providers may not always report a model name.
    let model: String?

    /// Detected source language of the selection (e.g. "German"), or `nil` if unknown.
    let language: String?

    /// End-to-end latency from request start to response received.
    let latencyMs: Int

    /// Original selected text. Decrypted, in-memory only.
    let input: String

    /// Generated AI response. Decrypted, in-memory only.
    let output: String
}
