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
    private var session: URLSession?
    private var destinationURL: URL?

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        let s = URLSession(configuration: cfg, delegate: nil, delegateQueue: .main)
        self.session = s
    }

    func download(_ model: WhisperModel) {
        guard downloadingModel == nil else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: WhisperConfig.appModelDirectory,
                                withIntermediateDirectories: true)

        downloadingModel = model.id
        downloadProgress = 0
        downloadError = nil
        destinationURL = model.localURL

        let task = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] tempURL, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.downloadingModel = nil
                self.downloadProgress = 0

                if let error {
                    self.downloadError = error.localizedDescription
                    return
                }
                guard let tempURL,
                      let dest = self.destinationURL else { return }

                do {
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.moveItem(at: tempURL, to: dest)
                    // Clear any manual model path override so auto-detection picks this up
                    UserDefaults.standard.removeObject(forKey: "voice.whisperModelPath")
                } catch {
                    self.downloadError = error.localizedDescription
                }
            }
        }

        // Track progress via observation
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        // Keep observation alive for the duration of the download
        objc_setAssociatedObject(task, "progressObs", observation, .OBJC_ASSOCIATION_RETAIN)

        downloadTask = task
        task.resume()
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModel = nil
        downloadProgress = 0
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: model.localURL)
    }
}
