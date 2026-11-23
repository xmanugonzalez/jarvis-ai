import AVFoundation
import Speech

@MainActor
final class SpeechRecognitionService {
    enum Event {
        case partial(String), final(String), failed(Error, partial: String?)
    }

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var configurationObserver: NSObjectProtocol?
    private var runID: UUID?
    private(set) var inputFormatDescription = "Sin formato de captura"
    private(set) var availabilityDescription = "Sin comprobar"

    var taskStatus: String {
        guard let task else { return "Sin tarea activa" }
        switch task.state {
        case .starting: return "Iniciando"
        case .running: return "Reconociendo"
        case .finishing: return "Finalizando"
        case .canceling: return "Cancelando"
        case .completed: return "Completada"
        @unknown default: return "Estado \(task.state.rawValue)"
        }
    }

    static func authorize() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    func start(settings: AssistantSettings, onEvent: @escaping (Event) -> Void) throws {
        let locale = Locale(identifier: settings.language.rawValue)
        guard SFSpeechRecognizer.supportedLocales().contains(where: {
            $0.identifier.replacingOccurrences(of: "_", with: "-").caseInsensitiveCompare(settings.language.rawValue) == .orderedSame
        }),
              let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AssistantError.unsupportedSpeechLanguage
        }
        let supportsLocal = recognizer.supportsOnDeviceRecognition
        let available = recognizer.isAvailable
        availabilityDescription = "Disponible: \(available). Compatible con modo local: \(supportsLocal)."
        if settings.offlineOnly && !supportsLocal {
            throw AssistantError.offlineUnavailable
        }
        guard available else { throw AssistantError.speechUnavailable }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.inputFormat(forBus: 0)
        let format = input.outputFormat(forBus: 0)
        inputFormatDescription = "Hardware: \(hardwareFormat). Captura: \(format)."
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
              format.sampleRate > 0, format.channelCount > 0 else { throw AssistantError.noInput }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = settings.offlineOnly
        let runID = UUID()
        self.runID = runID
        self.request = request
        self.engine = engine
        self.recognizer = recognizer

        // Serialize callbacks before handing them to the state machine on the main queue.
        let callbackQueue = OperationQueue()
        callbackQueue.maxConcurrentOperationCount = 1
        recognizer.queue = callbackQueue
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            DispatchQueue.main.async {
                guard self?.runID == runID else { return }
                if let error {
                    onEvent(.failed(error, partial: transcript))
                } else if final, let transcript {
                    onEvent(.final(transcript))
                } else if let transcript {
                    onEvent(.partial(transcript))
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            if buffer.frameLength > 0 { request.append(buffer) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            cancel()
            throw error
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.runID == runID, let engine = self.engine, !engine.isRunning else { return }
                onEvent(.failed(AssistantError.captureChanged, partial: nil))
            }
        }
    }

    func finishInput() {
        guard engine != nil else { return }
        stopCapture()
        request?.endAudio()
    }

    func complete() {
        finishInput()
        clear(cancelTask: false)
    }

    func cancel() {
        clear(cancelTask: true)
    }

    func resetDiagnostics() {
        inputFormatDescription = "Sin formato de captura"
        availabilityDescription = "Sin comprobar"
    }

    private func clear(cancelTask: Bool) {
        runID = nil
        stopCapture()
        if cancelTask { task?.cancel() }
        task = nil
        request = nil
        recognizer = nil
    }

    private func stopCapture() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }
}
