import Foundation

// MARK: - Model catalog

struct WhisperModel: Identifiable, Hashable {
    let id: String          // e.g. "base.en"
    let displayName: String // e.g. "Base (English)"
    let filename: String    // e.g. "ggml-base.en.bin"
    let sizeMB: Int
    let languages: String   // "English only" / "Multilingual"

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    var localURL: URL {
        WhisperConfig.appModelDirectory.appendingPathComponent(filename)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }

    static let catalog: [WhisperModel] = [
        WhisperModel(id: "tiny.en",  displayName: "Tiny (English)",        filename: "ggml-tiny.en.bin",  sizeMB:  77,  languages: "English only"),
        WhisperModel(id: "base.en",  displayName: "Base (English)",        filename: "ggml-base.en.bin",  sizeMB: 148,  languages: "English only"),
        WhisperModel(id: "base",     displayName: "Base (Multilingual)",   filename: "ggml-base.bin",     sizeMB: 148,  languages: "Multilingual"),
        WhisperModel(id: "small.en", displayName: "Small (English)",       filename: "ggml-small.en.bin", sizeMB: 488,  languages: "English only"),
        WhisperModel(id: "small",    displayName: "Small (Multilingual)",  filename: "ggml-small.bin",    sizeMB: 488,  languages: "Multilingual"),
    ]
}

// MARK: - Download manager

@MainActor
final class WhisperModelManager: NSObject, ObservableObject {
    @Published var downloadingModel: String? = nil   // model.id while downloading
    @Published var downloadProgress: Double  = 0     // 0…1
    @Published var downloadError: String?    = nil

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private var destinationURL: URL?
    /// Bumped on every download() and cancel() so a stale (cancelled/superseded)
    /// completion handler can detect it no longer owns the manager state and bail
    /// instead of clobbering a newer download.
    private var downloadGeneration = 0

    func download(_ model: WhisperModel) {
        guard downloadingModel == nil else { return }

        let fm = FileManager()
        try? fm.createDirectory(at: WhisperConfig.appModelDirectory,
                                withIntermediateDirectories: true)

        downloadGeneration &+= 1
        let generation = downloadGeneration
        downloadingModel = model.id
        downloadProgress = 0
        downloadError = nil
        destinationURL = model.localURL

        let task = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] tempURL, response, error in
            // URLSession only guarantees the temp file until this handler
            // returns — stage it synchronously before hopping to the MainActor.
            var stagedURL: URL?
            if let tempURL {
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tippi-model-\(UUID().uuidString).tmp")
                if (try? FileManager.default.moveItem(at: tempURL, to: staging)) != nil {
                    stagedURL = staging
                }
            }
            let staged = stagedURL

            Task { @MainActor [weak self] in
                guard let self else {
                    if let staged { try? FileManager.default.removeItem(at: staged) }
                    return
                }
                // A completion from a cancelled/superseded download must not touch
                // current state — otherwise it clears a newer download's marker
                // and lets two downloads race on the shared destinationURL.
                guard self.downloadGeneration == generation else {
                    if let staged { try? FileManager.default.removeItem(at: staged) }
                    return
                }
                self.downloadingModel = nil
                self.downloadProgress = 0

                if let error {
                    if let staged { try? FileManager.default.removeItem(at: staged) }
                    // A user-initiated cancel is not an error worth surfacing.
                    if (error as NSError).code != NSURLErrorCancelled {
                        self.downloadError = error.localizedDescription
                    }
                    return
                }

                // Guard against CDN error pages returned as HTTP 200 HTML
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    if let staged { try? FileManager.default.removeItem(at: staged) }
                    self.downloadError = "Download failed: server returned HTTP \(http.statusCode). Try again later."
                    return
                }

                guard let staged,
                      let dest = self.destinationURL else { return }

                do {
                    let localFM = FileManager()
                    if localFM.fileExists(atPath: dest.path) {
                        try localFM.removeItem(at: dest)
                    }
                    try localFM.moveItem(at: staged, to: dest)

                    // Sanity-check: real models start at ~77 MB; anything smaller is an error page
                    let attrs = try localFM.attributesOfItem(atPath: dest.path)
                    if let size = attrs[.size] as? Int64, size < 10_000_000 {
                        try? localFM.removeItem(at: dest)
                        self.downloadError = "Download failed: file too small (\(size / 1024) KB). Check your network connection and try again."
                        return
                    }

                    // Make the downloaded model the active model explicitly.
                    WhisperConfig.modelPath = model.localURL.path
                } catch {
                    self.downloadError = error.localizedDescription
                }
            }
        }

        // Track progress via observation, retained as a property for the
        // download's lifetime (stable storage instead of a string-keyed
        // associated object).
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        downloadTask = task
        task.resume()
    }

    func cancel() {
        // Invalidate any in-flight completion so its late MainActor hop can't
        // reset downloadingModel after a new download has already started.
        downloadGeneration &+= 1
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation = nil
        downloadingModel = nil
        downloadProgress = 0
    }

    func delete(_ model: WhisperModel) {
        // Cancel an in-flight download of this exact model first — otherwise the
        // completion handler would write the file back right after we delete it.
        if downloadingModel == model.id {
            cancel()
        }
        let wasActive = WhisperConfig.modelPath == model.localURL.path
        try? FileManager.default.removeItem(at: model.localURL)
        // Clear a stored path pointing at the deleted file so the config
        // falls back to auto-detecting any other installed model.
        if wasActive {
            WhisperConfig.modelPath = ""
        }
    }
}
