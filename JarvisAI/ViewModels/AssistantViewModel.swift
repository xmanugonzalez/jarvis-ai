import AVFoundation
import Combine
import Foundation
import OSLog

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published private(set) var state: AssistantState = .ready {
        didSet {
            guard state != oldValue else { return }
            wakeLogger.info("Estado: \(state.title, privacy: .public). Micrófono: \(microphoneActive, privacy: .public)")
        }
    }
    @Published private(set) var jarvisActive = false
    @Published private(set) var route = AudioRoute()
    @Published private(set) var transcript = ""
    @Published private(set) var response = ""
    @Published private(set) var recognitionMode = ""
    @Published private(set) var hasRecording = false
    @Published private(set) var notice: AssistantNotice?
    @Published private(set) var recognitionDiagnostic: String?
    @Published var settings: AssistantSettings {
        didSet { settings.save(to: defaults) }
    }

    private let defaults: UserDefaults
    private let audio = AudioSessionService()
    private let recognition = SpeechRecognitionService()
    private let wake = WakeWordService()
    let kokoroModel = KokoroModelStore()
    private let kokoro = KokoroSpeechOutputService()
    private let synthesisLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JarvisAI", category: "Synthesis")
    private let audioTest = AudioTestService(directory: FileManager.default.temporaryDirectory)
    private let wakeLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JarvisAI", category: "HandsFree")
    private let clock = ContinuousClock()
    private var turnBegan: ContinuousClock.Instant?
    private var lastVoice: ContinuousClock.Instant?
    private var turnMonitor: Task<Void, Never>?
    private var followUp = false
    private var currentTranscript = ""
    private enum Recovery { case interruption(requireHFP: Bool), headset }
    private var recovery: Recovery?
    private var operationID: UUID?
    private var setup: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private let speechLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JarvisAI", category: "Speech")

    var isIdle: Bool { state == .ready }
    var microphoneActive: Bool { wake.microphoneActive || state == .listening || state == .recording }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AssistantSettings(defaults: defaults)
        route = audio.snapshot()
        audio.onEvent = { [weak self] event in self?.handle(event) }
    }

    func foregrounded() {
        if jarvisActive && state != .preparing && !wake.microphoneActive {
            end("iOS pausó la captura de audio. Reactiva el Modo JARVIS en Inicio.")
        }
        if isIdle { route = audio.snapshot() }
    }

    func backgrounded() {
        if !isIdle && (!jarvisActive || state == .preparing) {
            end("La escucha se detuvo al salir de la app. Puedes reactivar el Modo JARVIS en Inicio.")
        }
    }

    func setJarvisMode(_ enabled: Bool) {
        if enabled {
            guard isIdle else { return }
            settings.jarvisEnabled = true
            startJarvis()
        } else {
            settings.jarvisEnabled = false
            recovery = nil
            if jarvisActive { end() }
        }
    }

    private func startJarvis(requireHFP: Bool = false) {
        guard isIdle else { return }
        recovery = nil
        jarvisActive = true
        transcript = ""
        response = ""
        begin(diagnoseSpeech: true) { model, _ in
            guard model.kokoroModel.installedFolder != nil else { throw KokoroError.unavailable }
            try await model.authorizeSpeech()
            try await model.activate(handsFree: true, requireHFP: requireHFP)
            model.prepareKokoro()
            model.waitForWake()
        }
    }

    private func waitForWake(_ message: String? = nil) {
        deadline?.cancel()
        turnMonitor?.cancel()
        recognition.cancel()
        wake.discardAudio()
        recognitionMode = ""
        notice = message.map { AssistantNotice(message: $0) }
        guard jarvisActive, let id = operationID else { return }
        guard audio.active else {
            end("La sesión de audio se cerró. Reactiva el Modo JARVIS en Inicio.")
            return
        }
        do {
            try wake.start(detected: { [weak self] in
                guard let self, self.operationID == id, self.state == .waitingWake else { return }
                self.wakeDetected()
            }, failed: { [weak self] error in
                guard let self, self.operationID == id, self.jarvisActive else { return }
                self.end(error.localizedDescription)
            })
            state = .waitingWake
        } catch {
            end(error.localizedDescription)
        }
    }

    private func wakeDetected() {
        wakeLogger.info("Se detectó la palabra Jarvis.")
        wake.discardAudio()
        transcript = ""
        response = ""
        notice = nil
        state = .cue
        do {
            let delay = try wake.playCue()
            setDeadline(delay) { model in
                model.wake.discardAudio()
                model.startHandsFreeTurn(followUp: false)
            }
        } catch {
            end("No se pudo reproducir la confirmación. Comprueba la salida de audio.")
        }
    }

    func startListening() {
        guard isIdle else { return }
        transcript = ""
        response = ""
        begin(diagnoseSpeech: true) { model, id in
            try await model.authorizeSpeech()
            try await model.activate()
            try model.startRecognition(id: id, automatic: false)
            model.setDeadline(.seconds(45)) { $0.finishListening() }
        }
    }

    private func authorizeSpeech() async throws {
        try await authorizeMicrophone()
        let status = await SpeechRecognitionService.authorize()
        try Task.checkCancellation()
        if status == .restricted { throw AssistantError.speechRestricted }
        guard status == .authorized else { throw AssistantError.speechPermission }
    }

    private func startRecognition(id: UUID, automatic: Bool) throws {
        currentTranscript = ""
        lastVoice = nil
        turnBegan = clock.now
        recognitionMode = settings.offlineOnly ? "Local en el iPhone" : "Automático de Apple"
        recognition.resetDiagnostics()
        guard !audio.snapshot().inputs.isEmpty else { throw AssistantError.noInput }
        let activity: (() -> Void)?
        if automatic {
            activity = { [weak self] in
                guard let self, self.operationID == id, self.state == .listening else { return }
                self.lastVoice = self.clock.now
            }
        } else {
            activity = nil
        }
        try recognition.start(settings: settings, onVoiceActivity: activity, capture: automatic ? wake : nil) { [weak self] event in
            self?.handleRecognition(event, id: id)
        }
        state = .listening
    }

    private func startHandsFreeTurn(followUp: Bool) {
        guard jarvisActive, let id = operationID, audio.active else {
            end("La escucha se pausó. Reactiva el Modo JARVIS en Inicio.")
            return
        }
        self.followUp = followUp
        do {
            try startRecognition(id: id, automatic: true)
        } catch {
            failRecognition(error)
            return
        }
        let timing = HandsFreeTurn(startLimit: followUp ? settings.conversationSeconds : 8,
                                   silenceLimit: settings.silenceSeconds)
        turnMonitor?.cancel()
        turnMonitor = Task { [weak self] in
            while (try? await Task.sleep(for: .milliseconds(200))) != nil {
                guard !Task.isCancelled, let self, self.operationID == id,
                      self.state == .listening, let began = self.turnBegan else { return }
                let elapsed = Self.seconds(began.duration(to: self.clock.now))
                let activity = self.lastVoice.map { Self.seconds(began.duration(to: $0)) }
                switch timing.decision(elapsed: elapsed, lastSpeech: activity, hasText: !self.currentTranscript.isEmpty) {
                case .keepListening: continue
                case .noSpeech:
                    self.wakeLogger.info("Turno sin instrucción. Se rearma el detector.")
                    self.waitForWake()
                case .silence, .timeLimit: self.finishListening()
                }
                return
            }
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func finishListening() {
        guard state == .listening else { return }
        turnMonitor?.cancel()
        state = .processing
        recognition.finishInput()
        setDeadline(.seconds(10)) { $0.failRecognition(AssistantError.speechTimedOut) }
    }

    func previewKokoro() {
        begin { model, _ in
            try await model.activate()
            model.speak("Buenas noches, señor. JARVIS está operativo.")
        }
    }

    func prepareKokoro() {
        kokoro.prepare(model: kokoroModel.installedFolder)
    }

    func removeKokoroModel() {
        guard isIdle else { return }
        kokoro.purge()
        kokoroModel.remove()
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
        if jarvisActive {
            setJarvisMode(false)
        } else {
            end()
        }
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
                } else if let error = error as? KokoroError {
                    self.end(error.localizedDescription)
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

    private func activate(handsFree: Bool = false, requireHFP: Bool = false) async throws {
        try Task.checkCancellation()
        let currentRoute = try await audio.activate(settings: settings, handsFree: handsFree, requireHFP: requireHFP)
        try Task.checkCancellation()
        route = currentRoute
        wakeLogger.info("Ruta: entrada \(currentRoute.inputs.joined(separator: ", "), privacy: .private); salida \(currentRoute.outputs.joined(separator: ", "), privacy: .private); HFP: \(currentRoute.usesHFP, privacy: .public)")
    }

    private func handleRecognition(_ event: SpeechRecognitionService.Event, id: UUID) {
        guard operationID == id, state == .listening || state == .processing else { return }
        switch event {
        case .partial(let text):
            if updateTranscript(text), lastVoice == nil { lastVoice = clock.now }
        case .final(let text):
            _ = updateTranscript(text)
            answer()
        case .failed(let error, let partial):
            if let partial { _ = updateTranscript(partial) }
            failRecognition(error)
        }
    }

    @discardableResult
    private func updateTranscript(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != currentTranscript else { return false }
        currentTranscript = text
        transcript = text
        return true
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
        let notice = currentTranscript.isEmpty ? message : "\(message) Se conservó la transcripción parcial."
        if jarvisActive {
            waitForWake(notice)
        } else {
            end(notice)
        }
    }

    private func answer() {
        deadline?.cancel()
        turnMonitor?.cancel()
        recognition.complete()
        if let began = turnBegan {
            wakeLogger.info("Reconocimiento: \(Self.seconds(began.duration(to: clock.now)), privacy: .public) s.")
        }
        guard !currentTranscript.isEmpty else {
            if jarvisActive { waitForWake() } else { end("No se detectó voz. Vuelve a intentarlo.") }
            return
        }
        if jarvisActive && followUp, LocalResponses.recognizedReply(to: currentTranscript, followUp: true) == nil {
            waitForWake()
            return
        }
        response = LocalResponses.reply(to: currentTranscript)
        speak(response)
    }

    private func speak(_ text: String) {
        let current = audio.snapshot()
        guard !current.outputs.isEmpty else { end(AssistantError.noOutput.localizedDescription); return }
        guard current.signature == route.signature else {
            end("Cambió la ruta de audio. Comprueba los dispositivos y vuelve a intentarlo.")
            return
        }
        let id = operationID
        let started = clock.now
        state = .speaking
        do {
            try kokoro.speak(text, settings: settings, model: kokoroModel.installedFolder, onPlaybackStarted: { [weak self] in
                guard let self, self.operationID == id else { return }
                self.wakeLogger.info("Generación Kokoro: \(Self.seconds(started.duration(to: self.clock.now)), privacy: .public) s.")
            }) { [weak self] error in
                guard let self, self.operationID == id else { return }
                if let error {
                    self.finishSpeechWithError(error)
                } else if self.jarvisActive && self.settings.conversationSeconds > 0 {
                    // Wait for the output tail before opening the microphone again.
                    self.setDeadline(.milliseconds(350)) { $0.startHandsFreeTurn(followUp: true) }
                } else if self.jarvisActive {
                    self.setDeadline(.milliseconds(350)) { $0.waitForWake() }
                } else {
                    self.end()
                }
            }
            setDeadline(.seconds(30)) { $0.finishSpeechWithError(KokoroError.timeout) }
        } catch {
            finishSpeechWithError(error)
        }
    }

    private func finishSpeechWithError(_ error: Error) {
        kokoro.cancel()
        synthesisLogger.error("Kokoro: \(error.localizedDescription, privacy: .public)")
        if jarvisActive, kokoroModel.installedFolder != nil {
            let message = error.localizedDescription
            notice = AssistantNotice(message: message)
            setDeadline(.milliseconds(350)) { $0.waitForWake(message) }
        } else {
            end(error.localizedDescription)
        }
    }

    private func setDeadline(_ duration: Duration, action: @escaping @MainActor (AssistantViewModel) -> Void) {
        let id = operationID
        deadline?.cancel()
        deadline = Task { [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil,
                  !Task.isCancelled, let self, self.operationID == id else { return }
            action(self)
        }
    }

    private func end(_ message: String? = nil, openSettings: Bool = false) {
        operationID = nil
        setup?.cancel()
        setup = nil
        deadline?.cancel()
        deadline = nil
        turnMonitor?.cancel()
        turnMonitor = nil
        wake.stop()
        recognition.cancel()
        kokoro.cancel()
        audioTest.cancel()
        jarvisActive = false
        audio.deactivate()
        hasRecording = audioTest.hasRecording
        notice = message.map { AssistantNotice(message: $0, openSettings: openSettings) }
        if let message { wakeLogger.notice("Pausa o error: \(message, privacy: .private)") }
        state = .ready
    }

    private func recoverJarvis(requireHFP: Bool) {
        guard settings.jarvisEnabled, isIdle, SpeechRecognitionService.isAuthorized,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        startJarvis(requireHFP: requireHFP)
    }

    private func handle(_ event: AudioSessionService.Event) {
        switch event {
        case .routeChanged(let reason):
            let current = audio.snapshot()
            switch state {
            case .waitingWake, .cue, .listening, .processing, .speaking, .recording, .playing:
                guard current.signature != route.signature else { route = current; return }
                let wasRecognizing = state == .listening || state == .processing
                if jarvisActive {
                    let lostHeadset = route.usesHFP && !current.usesHFP
                    route = current
                    if lostHeadset {
                        recovery = .headset
                        end("Se desconectó el manos libres. Reconecta el casco o reactiva el Modo JARVIS.")
                    } else if current.inputs.isEmpty || current.outputs.isEmpty {
                        end("Se perdió la ruta de audio. Reactiva el Modo JARVIS cuando esté disponible.")
                    } else {
                        kokoro.cancel()
                        wake.stop()
                        waitForWake("Cambió la ruta de audio. Di «Jarvis» para comenzar un nuevo turno.")
                    }
                } else {
                    route = current
                    if wasRecognizing {
                        failRecognition(AssistantError.captureChanged)
                    } else {
                        end("Cambió la ruta de audio. Comprueba los dispositivos y vuelve a intentarlo.")
                    }
                }
            case .ready:
                if reason != .override && reason != .categoryChange { route = current }
                if reason == .newDeviceAvailable, case .headset? = recovery {
                    recoverJarvis(requireHFP: true)
                }
            case .preparing, .checking:
                break
            }
        case .interrupted:
            if jarvisActive { recovery = .interruption(requireHFP: route.usesHFP) }
            route = audio.snapshot()
            if !isIdle { end("iOS interrumpió el audio. Puedes reactivar el Modo JARVIS cuando termine.") }
        case .interruptionEnded(let shouldResume):
            if isIdle { route = audio.snapshot() }
            if shouldResume, case .interruption(let requireHFP)? = recovery {
                recoverJarvis(requireHFP: requireHFP)
            }
        case .mediaReset:
            route = AudioRoute()
            recovery = nil
            end("iOS reinició el audio. Reactiva el Modo JARVIS en Inicio.")
            kokoro.purge()
        }
    }
}
