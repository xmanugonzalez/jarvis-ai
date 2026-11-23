import AVFoundation
import SherpaOnnx

// All native engine access stays on this serial queue.
private final class KokoroWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.jarvisai.kokoro", qos: .userInitiated)
    private var engine: SherpaOnnxOfflineTtsWrapper?
    private static let speakerID = 29 // em_alex in Kokoro multilingual v1.0

    func render(_ text: String, speed: Float, model: URL, data: URL,
                completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        queue.async {
            completion(Result {
                try autoreleasepool {
                    let engine = try self.load(model: model, data: data)
                    let audio = engine.generate(text: text, sid: Self.speakerID, speed: speed)
                    guard audio.audio != nil, audio.n > 0, audio.sampleRate > 0 else { throw KokoroError.synthesis }
                    let wave = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
                    defer { try? FileManager.default.removeItem(at: wave) }
                    guard audio.save(filename: wave.path) != 0 else { throw KokoroError.synthesis }
                    return try Data(contentsOf: wave)
                }
            })
        }
    }

    func prepare(model: URL, data: URL) {
        queue.async {
            autoreleasepool { _ = try? self.load(model: model, data: data) }
        }
    }

    func purge() {
        queue.async { self.engine = nil }
    }

    private func load(model: URL, data: URL) throws -> SherpaOnnxOfflineTtsWrapper {
        if let engine { return engine }
        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: model.appendingPathComponent("model.int8.onnx").path,
            voices: model.appendingPathComponent("voices.bin").path,
            tokens: model.appendingPathComponent("tokens.txt").path,
            dataDir: data.path,
            lang: "es"
        )
        let config = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoro, numThreads: 2, provider: "cpu")
        var ttsConfig = sherpaOnnxOfflineTtsConfig(model: config)
        let engine = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        guard engine.tts != nil, engine.numSpeakers > Int32(Self.speakerID) else { throw KokoroError.synthesis }
        self.engine = engine
        return engine
    }
}

@MainActor
final class KokoroSpeechOutputService: NSObject, AVAudioPlayerDelegate {
    private let worker = KokoroWorker()
    private var rendering = false
    private var requestID: UUID?
    private var deadline: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var completion: ((Error?) -> Void)?

    private var phonemizerData: URL? {
        guard let data = Bundle.main.url(forResource: "espeak-ng-data", withExtension: nil, subdirectory: "KokoroSupport"),
              FileManager.default.isReadableFile(atPath: data.appendingPathComponent("es_dict").path) else {
            return nil
        }
        return data
    }

    func prepare(model: URL?) {
        guard let model, let data = phonemizerData else { return }
        worker.prepare(model: model, data: data)
    }

    func speak(_ text: String, settings: AssistantSettings, model: URL?,
               onPlaybackStarted: (() -> Void)? = nil,
               completion: @escaping (Error?) -> Void) throws {
        guard !rendering else { throw KokoroError.busy }
        guard let model, let data = phonemizerData else {
            throw KokoroError.unavailable
        }
        guard !text.isEmpty, text.utf8.count <= 512 else { throw KokoroError.synthesis }

        let id = UUID()
        let speed = Float(min(max(settings.speechRate / 0.46, 0.80), 1.25))
        let volume = Float(settings.speechVolume)
        requestID = id
        rendering = true
        self.completion = completion
        deadline = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(10))) != nil,
                  let self, self.requestID == id else { return }
            self.finish(error: KokoroError.timeout)
        }

        worker.render(text, speed: speed, model: model, data: data) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.rendering = false
                guard self.requestID == id else { return }
                self.deadline?.cancel()
                self.deadline = nil
                do {
                    let player = try AVAudioPlayer(data: result.get())
                    player.delegate = self
                    player.volume = volume
                    self.player = player
                    guard player.play() else { throw KokoroError.synthesis }
                    onPlaybackStarted?()
                } catch {
                    self.finish(error: error)
                }
            }
        }
    }

    func cancel() {
        completion = nil
        finish(error: nil)
    }

    func purge() {
        cancel()
        worker.purge()
    }

    private func finish(error: Error?) {
        let callback = completion
        completion = nil
        requestID = nil
        deadline?.cancel()
        deadline = nil
        player?.stop()
        player = nil
        callback?(error)
    }

    private func playerFinished(_ id: ObjectIdentifier, success: Bool) {
        guard let player, ObjectIdentifier(player) == id else { return }
        finish(error: success ? nil : KokoroError.synthesis)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerFinished(id, success: flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerFinished(id, success: false) }
    }
}
