import Foundation
import os

private let liveSyncLog = Logger(subsystem: "com.tippi.app", category: "notes-live-sync")

/// Watches the iCloud Notes folder and reports which files changed.
///
/// Why this exists (2026-09-20): `NotesStore` read from disk only on
/// `refresh()`, and `refresh()` ran only when the Notes window opened. A note
/// written on the other Mac arrived in the container here and stayed invisible
/// for as long as the window sat open — reported as "notes don't sync", though
/// the transport was never the problem. A focus-triggered refresh shipped in
/// 2.11.4 and covers the everyday case (switch Mac, click the window); this
/// closes the remaining one, two windows open side by side.
///
/// **It reports additions and changes only — never removals.** In a ubiquity
/// container, "the file is not there" is ambiguous: it can also mean not yet
/// downloaded, evicted to free space, or mid-rename by the sync daemon. Notes
/// are hard-deleted without a trash (see `NotesStore.delete`), so treating
/// absence as a deletion would destroy data that nobody can get back. A
/// deletion made on this Mac still works normally; one made on the other Mac
/// shows up on the next full `refresh()`, which is the conservative direction.
@MainActor
final class NotesLiveSync {
    /// Called with the URLs of note files that appeared or changed.
    private let onChange: ([URL]) -> Void

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping ([URL]) -> Void) {
        self.onChange = onChange
    }

    deinit {
        // Not `stop()` — that is main-actor isolated and deinit is not. The
        // query stops itself when released; the observers must go explicitly,
        // or they fire into a freed object.
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    var isRunning: Bool { query?.isStarted ?? false }

    /// Starts watching `directory`. Safe to call repeatedly — a running query
    /// for a different directory is replaced, one for the same directory is
    /// left alone so an in-flight gather is not restarted.
    func start(watching directory: URL) {
        if let existing = query,
           existing.isStarted,
           (existing.searchScopes.first as? URL)?.standardizedFileURL == directory.standardizedFileURL {
            return
        }
        stop()

        let query = NSMetadataQuery()
        // Scope by the actual directory rather than
        // `NSMetadataQueryUbiquitousDocumentsScope`: the latter covers the whole
        // Documents tree of the container, and every unrelated file in it would
        // wake this up.
        query.searchScopes = [directory]
        query.predicate = NSPredicate(format: "%K ENDSWITH[c] %@", NSMetadataItemFSNameKey, ".txt")
        // Notes are small; batching would only add latency to the one thing
        // this is for.
        query.notificationBatchingInterval = 0.5

        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering,
                     NSNotification.Name.NSMetadataQueryDidUpdate] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: query, queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated { self?.handle(note) }
            }
            observers.append(observer)
        }

        self.query = query
        query.start()
        liveSyncLog.notice("live sync started for \(directory.lastPathComponent, privacy: .public)")
    }

    func stop() {
        query?.stop()
        query = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func handle(_ notification: Notification) {
        guard let query else { return }

        // `NSMetadataQueryUpdateRemovedItemsKey` is deliberately ignored — see
        // the type comment. Absence in a ubiquity container is not deletion.
        let info = notification.userInfo ?? [:]
        let added = info[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
        let changed = info[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []

        let items: [NSMetadataItem]
        if added.isEmpty && changed.isEmpty {
            // The initial gather carries no change lists; every result counts.
            query.disableUpdates()
            items = (0..<query.resultCount).compactMap { query.result(at: $0) as? NSMetadataItem }
            query.enableUpdates()
        } else {
            items = added + changed
        }

        let urls = Self.downloadableURLs(from: items)
        guard !urls.isEmpty else { return }
        liveSyncLog.debug("live sync reporting \(urls.count, privacy: .public) changed file(s)")
        onChange(urls)
    }

    /// URLs that are worth reading right now. A file that has not finished
    /// downloading is requested and skipped — it arrives as another update once
    /// it is local, rather than being read half-written.
    private static func downloadableURLs(from items: [NSMetadataItem]) -> [URL] {
        items.compactMap { item in
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if let status, status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                return nil
            }
            return url
        }
    }
}
