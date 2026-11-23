import AVFoundation
import Combine
import Foundation
import OSLog

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published private(set) var state: AssistantState = .ready
    @Published private(set) var route = AudioRoute()
    @Published private(set) var transcript = ""
    @Published private(set) var response = ""
    @Published private(set) var recognitionMode = ""
    @Published private(set) var hasRecording = false
    @Published private(set) var voices: [SpanishVoice] = []
    @Published private(set) var notice: AssistantNotice?
    @Published private(set) var recognitionDiagnostic: String?
    @Published var settings: AssistantSettings {
        didSet {
            settings.save(to: defaults)
            if settings.voiceEngine == .kokoro && oldValue.voiceEngine != .kokoro { prepareKokoro() }
        }
    }

    private let defaults: UserDefaults
    private let audio = AudioSessionService()
    private let recognition = SpeechRecognitionService()
    private let speech: any SpeechSynthesisProvider = SpeechOutputService()
    let kokoroModel = KokoroModelStore()
    private let kokoro = KokoroSpeechOutputService()
    private let synthesisLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JarvisAI", category: "Synthesis")
    private let audioTest = AudioTestService(directory: FileManager.default.temporaryDirectory)
    private var operationID: UUID?
    private var setup: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private let speechLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JarvisAI", category: "Speech")

    var isIdle: Bool { state == .ready }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AssistantSettings(defaults: defaults)
        route = audio.snapshot()
        voices = speech.voices()
        audio.onEvent = { [weak self] event in self?.handle(event) }
    }

    func foregrounded() {
        refreshVoices()
        if settings.voiceEngine == .kokoro { prepareKokoro() }
        if isIdle { route = audio.snapshot() }
    }

    func refreshVoices() {
        voices = speech.voices()
    }

    func backgrounded() {
        if !isIdle { end("El audio se detuvo al salir de la app.") }
    }

    func startListening() {
        guard isIdle else { return }
        transcript = ""
        response = ""
        recognitionMode = settings.offlineOnly ? "Local en el iPhone" : "Automático de Apple"
        recognition.resetDiagnostics()
        begin(diagnoseSpeech: true) { model, id in
            try await model.authorizeMicrophone()
            let status = await SpeechRecognitionService.authorize()
            try Task.checkCancellation()
            if status == .restricted { throw AssistantError.speechRestricted }
            guard status == .authorized else { throw AssistantError.speechPermission }
            try await model.activate()
            guard !model.route.inputs.isEmpty else { throw AssistantError.noInput }
            try model.recognition.start(settings: model.settings) { [weak model] event in
                model?.handleRecognition(event, id: id)
            }
            model.state = .listening
            model.setDeadline(.seconds(45)) { $0.finishListening() }
        }
    }

    func finishListening() {
        guard state == .listening else { return }
        state = .processing
        recognition.finishInput()
        setDeadline(.seconds(10)) { $0.failRecognition(AssistantError.speechTimedOut) }
    }

    func previewVoice(_ voiceID: String? = nil) {
        preview(engine: .apple, voiceID: voiceID)
    }

    func previewKokoro() {
        preview(engine: .kokoro, voiceID: nil)
    }

    func prepareKokoro() {
        kokoro.prepare(model: kokoroModel.installedFolder)
    }

    func removeKokoroModel() {
        guard isIdle else { return }
        kokoro.purge()
        kokoroModel.remove()
    }

    private func preview(engine: VoiceEngine, voiceID: String?) {
        begin { model, _ in
            try await model.activate()
            model.speak("Buenas noches, señor. JARVIS está operativo.",
                        engine: engine, previewVoiceID: voiceID)
        }
    }

    func checkRoute() {
        begin(initialState: .checking) { model, _ in
            try await model.activate()
            model.end()
        }
    }

    func toggleRecording() {
        if state == .recording {
            audioTest.finishRecording()
            return
        }
        begin { model, id in
            try await model.authorizeMicrophone()
            try await model.activate()
            guard !model.route.inputs.isEmpty else { throw AssistantError.noInput }
            try model.audioTest.record { [weak model] success in
                guard let model, model.operationID == id else { return }
                model.end(success ? "Grabación lista para reproducir." : AssistantError.recordingFailed.localizedDescription)
            }
            model.state = .recording
        }
    }

    func playRecording() {
        if state == .playing {
            end()
            return
        }
        guard hasRecording else { return }
        begin { model, id in
            try await model.activate()
            guard !model.route.outputs.isEmpty else { throw AssistantError.noOutput }
            try model.audioTest.play { [weak model] success in
                guard let model, model.operationID == id else { return }
                model.end(success ? nil : AssistantError.playbackFailed.localizedDescription)
            }
            model.state = .playing
        }
    }

    func stop() {
        end()
    }

    private func begin(
        initialState: AssistantState = .preparing,
        diagnoseSpeech: Bool = false,
        action: @escaping @MainActor (AssistantViewModel, UUID) async throws -> Void
    ) {
        guard isIdle else { return }
        let id = UUID()
        operationID = id
        notice = nil
        state = initialState
        setup = Task { [weak self] in
            guard let self else { return }
            do {
                try await action(self, id)
            } catch {
                guard self.operationID == id else { return }
                if diagnoseSpeech { self.recordRecognitionFailure(error) }
                if let error = error as? AssistantError {
                    let needsSettings = error == .microphonePermission || error == .speechPermission
                    self.end(error.localizedDescription, openSettings: needsSettings)
                } else {
                    self.end("No se pudo iniciar el audio. Comprueba la ruta y vuelve a intentarlo.")
                }
            }
        }
    }

    private func authorizeMicrophone() async throws {
        let granted = await AudioTestService.authorizeMicrophone()
        try Task.checkCancellation()
        guard granted else { throw AssistantError.microphonePermission }
    }

    private func activate() async throws {
        try Task.checkCancellation()
        let currentRoute = try await audio.activate(settings: settings)
        try Task.checkCancellation()
        route = currentRoute
    }

    private func handleRecognition(_ event: SpeechRecognitionService.Event, id: UUID) {
        guard operationID == id, state == .listening || state == .processing else { return }
        switch event {
        case .partial(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { transcript = text }
        case .final(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { transcript = text }
            answer()
        case .failed(let error, let partial):
            if let partial, !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { transcript = partial }
            failRecognition(error)
        }
    }

    private func recordRecognitionFailure(_ error: Error) {
        let original = error as NSError
        let details = """
        Dominio: \(original.domain)
        Código: \(original.code)
        Descripción: \(original.localizedDescription)
        Estado: \(state.title) / \(recognition.taskStatus)
        Idioma: \(settings.language.rawValue)
        Método: \(recognitionMode)
        Servicio: \(recognition.availabilityDescription)
        \(audio.diagnosticDescription())
        Formato: \(recognition.inputFormatDescription)
        """
        recognitionDiagnostic = details
        speechLogger.error("\(original.domain, privacy: .public) [\(original.code, privacy: .public)] \(details, privacy: .private)")
    }

    private func failRecognition(_ error: Error) {
        recordRecognitionFailure(error)
        let message: String
        if let error = error as? AssistantError {
            message = error.localizedDescription
        } else if (error as NSError).domain == NSURLErrorDomain {
            message = "La conexión con Apple Speech falló. Comprueba internet y vuelve a intentarlo."
        } else {
            message = "Apple Speech interrumpió la escucha. Vuelve a intentarlo y consulta Configuración → Diagnóstico si vuelve a ocurrir."
        }
        end(transcript.isEmpty ? message : "\(message) Se conservó la transcripción parcial.")
    }

    private func answer() {
        deadline?.cancel()
        recognition.complete()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            end("No se detectó voz. Vuelve a intentarlo.")
            return
        }
        response = LocalResponses.reply(to: transcript)
        speak(response)
    }

    private func speak(_ text: String, engine: VoiceEngine? = nil, previewVoiceID: String? = nil,
                       fallbackNotice: String? = nil) {
        let current = audio.snapshot()
        guard !current.outputs.isEmpty else {
            end(AssistantError.noOutput.localizedDescription)
            return
        }
        guard current.signature == route.signature else {
            route = current
            end("Cambió la ruta de audio. Comprueba los dispositivos y vuelve a intentarlo.")
            return
        }
        let id = operationID
        state = .speaking
        if (engine ?? settings.voiceEngine) == .kokoro {
            let fallback: (Error) -> Void = { [weak self] error in
                guard let self, self.operationID == id else { return }
                self.synthesisLogger.error("Kokoro: \(error.localizedDescription, privacy: .public)")
                self.speak(text, engine: .apple, fallbackNotice: "Se usó la voz de Apple. \(error.localizedDescription)")
            }
            do {
                try kokoro.speak(text, settings: settings, model: kokoroModel.installedFolder) { [weak self] error in
                    guard let self, self.operationID == id else { return }
                    if let error {
                        fallback(error)
                    } else {
                        self.end()
                    }
                }
                setDeadline(.seconds(30)) {
                    $0.kokoro.cancel()
                    fallback(KokoroError.timeout)
                }
            } catch {
                fallback(error)
            }
            return
        }

        do {
            try speech.speak(text, settings: settings, previewVoiceID: previewVoiceID) { [weak self] success in
                guard let self, self.operationID == id else { return }
                self.end(success ? fallbackNotice : "La respuesta hablada se interrumpió.")
            }
            setDeadline(.seconds(20)) { $0.end("La respuesta hablada no se completó. Comprueba la voz y la salida de audio.") }
        } catch {
            end(error.localizedDescription)
        }
    }

    private func setDeadline(_ duration: Duration, action: @escaping @MainActor (AssistantViewModel) -> Void) {
        let id = operationID
        deadline?.cancel()
        deadline = Task { [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil,
                  let self, self.operationID == id else { return }
            action(self)
        }
    }

    private func end(_ message: String? = nil, openSettings: Bool = false) {
        operationID = nil
        setup?.cancel()
        setup = nil
        deadline?.cancel()
        deadline = nil
        recognition.cancel()
        kokoro.cancel()
        audioTest.cancel()
        speech.cancel()
        audio.deactivate()
        hasRecording = audioTest.hasRecording
        notice = message.map { AssistantNotice(message: $0, openSettings: openSettings) }
        state = .ready
    }

    private func handle(_ event: AudioSessionService.Event) {
        switch event {
        case .routeChanged(let reason):
            let current = audio.snapshot()
            switch state {
            case .listening, .processing, .speaking, .recording, .playing:
                if current.signature != route.signature {
                    let wasRecognizing = state == .listening || state == .processing
                    route = current
                    if wasRecognizing {
                        failRecognition(AssistantError.captureChanged)
                    } else {
                        end("Cambió la ruta de audio. Comprueba los dispositivos y vuelve a intentarlo.")
                    }
                } else {
                    route = current
                }
            case .ready:
                if reason != .override && reason != .categoryChange {
                    route = current
                }
            case .preparing, .checking:
                break
            }
        case .interrupted:
            route = audio.snapshot()
            if !isIdle {
                end("iOS interrumpió el audio. Vuelve a intentar cuando termine la interrupción.")
            }
        case .interruptionEnded:
            if isIdle { route = audio.snapshot() }
        case .mediaReset:
            route = AudioRoute()
            end("iOS reinició el audio. Vuelve a iniciar la prueba o la escucha.")
            speech.reset()
            kokoro.purge()
        }
    }
}
