import Foundation

/// Upload state of the notes folder, polled by `NotesStore` every 30 s.
/// Kept out of `NotesStore` so the store stays within its lint limits.
enum NotesUploadState {
    /// Counts note files iCloud reports as not uploaded and older than
    /// `minimumAge` — a fresh save needs a few seconds and must not flash the
    /// warning. Files outside iCloud report no upload state and never count.
    /// Same rule as TippAI (`NotesStore.pendingUploadCount`), both read this folder.
    static func pendingCount(
        in directory: URL,
        now: Date,
        minimumAge: TimeInterval = 60,
        uploadState: (URL) -> (isUploaded: Bool?, modifiedAt: Date?) = NotesUploadState.state(of:)
    ) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return 0 }
        return files.filter { url in
            guard url.pathExtension == NotesStore.fileExtension else { return false }
            let state = uploadState(url)
            guard state.isUploaded == false else { return false }
            guard let modified = state.modifiedAt else { return true }
            return now.timeIntervalSince(modified) >= minimumAge
        }.count
    }

    static func state(of url: URL) -> (isUploaded: Bool?, modifiedAt: Date?) {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .contentModificationDateKey
        ])
        guard values?.isUbiquitousItem == true else { return (nil, values?.contentModificationDate) }
        return (values?.ubiquitousItemIsUploaded, values?.contentModificationDate)
    }
}
