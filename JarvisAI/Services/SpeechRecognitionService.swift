import AVFoundation
import Speech

@MainActor
final class SpeechRecognitionService {
    enum Event {
        case partial(String), final(String), failed(String)
    }

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var configurationObserver: NSObjectProtocol?
    private var runID: UUID?

    static func authorize() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    func start(settings: AssistantSettings, onEvent: @escaping (Event) -> Void) throws -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: settings.language.rawValue)) else {
            throw AssistantError.speechUnavailable
        }
        let local = recognizer.supportsOnDeviceRecognition
        if settings.offlineOnly && !local {
            throw AssistantError.offlineUnavailable
        }
        guard local || recognizer.isAvailable else { throw AssistantError.speechUnavailable }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AssistantError.noInput }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = local
        let runID = UUID()
        self.runID = runID
        self.request = request
        self.engine = engine
        self.recognizer = recognizer

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                guard self?.runID == runID else { return }
                if final, let transcript {
                    onEvent(.final(transcript))
                } else if failed {
                    if let transcript { onEvent(.partial(transcript)) }
                    onEvent(.failed("Apple Speech no pudo terminar la transcripción. Vuelve a intentarlo."))
                } else if let transcript {
                    onEvent(.partial(transcript))
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
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
                onEvent(.failed("La configuración del micrófono cambió. Vuelve a escuchar."))
            }
        }
        return local
    }

    func finishInput() {
        stopCapture()
        request?.endAudio()
        task?.finish()
    }

    func cancel() {
        runID = nil
        stopCapture()
        task?.cancel()
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
