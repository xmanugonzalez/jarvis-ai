import AVFoundation
import Combine
import Foundation

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
    @Published var settings: AssistantSettings {
        didSet { settings.save(to: defaults) }
    }

    private let defaults: UserDefaults
    private let audio = AudioSessionService()
    private let recognition = SpeechRecognitionService()
    private let speech = SpeechOutputService()
    private let audioTest = AudioTestService(directory: FileManager.default.temporaryDirectory)
    private var operationID: UUID?
    private var setup: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var silence: Task<Void, Never>?

    var isIdle: Bool { state == .ready }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AssistantSettings(defaults: defaults)
        route = audio.snapshot()
        voices = speech.voices()
        audio.onEvent = { [weak self] event in self?.handle(event) }
    }

    func foregrounded() {
        voices = speech.voices()
        if isIdle { route = audio.snapshot() }
    }

    func backgrounded() {
        if !isIdle { end("El audio se detuvo al salir de la app.") }
    }

    func startListening() {
        guard isIdle else { return }
        transcript = ""
        response = ""
        recognitionMode = ""
        begin { model, id in
            try await model.authorizeMicrophone()
            let status = await SpeechRecognitionService.authorize()
            try Task.checkCancellation()
            if status == .restricted { throw AssistantError.speechRestricted }
            guard status == .authorized else { throw AssistantError.speechPermission }
            try await model.activate()
            guard !model.route.inputs.isEmpty else { throw AssistantError.noInput }
            let local = try model.recognition.start(settings: model.settings) { [weak model] event in
                model?.handleRecognition(event, id: id)
            }
            model.recognitionMode = local ? "En el iPhone" : "Con servicio de Apple"
            model.state = .listening
            model.setDeadline(.seconds(45)) { $0.finishListening() }
        }
    }

    func finishListening() {
        guard state == .listening else { return }
        state = .processing
        silence?.cancel()
        recognition.finishInput()
        setDeadline(.seconds(3)) { $0.answer() }
    }

    func previewVoice() {
        begin { model, _ in
            try await model.activate()
            model.speak("A sus órdenes, señor.")
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
            guard text != transcript else { return }
            transcript = text
            guard state == .listening, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            silence?.cancel()
            silence = Task { [weak self] in
                guard (try? await Task.sleep(for: .milliseconds(2400))) != nil,
                      let self, self.operationID == id else { return }
                self.finishListening()
            }
        case .final(let text):
            if !text.isEmpty { transcript = text }
            answer()
        case .failed(let message):
            if state == .processing, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                answer()
            } else {
                end(message)
            }
        }
    }

    private func answer() {
        deadline?.cancel()
        silence?.cancel()
        recognition.cancel()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            end("No se detectó voz. Vuelve a intentarlo.")
            return
        }
        response = LocalResponses.reply(to: transcript)
        speak(response)
    }

    private func speak(_ text: String) {
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
        do {
            try speech.speak(text, settings: settings) { [weak self] success in
                guard let self, self.operationID == id else { return }
                self.end(success ? nil : "La respuesta hablada se interrumpió.")
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
        silence?.cancel()
        silence = nil
        recognition.cancel()
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
                    route = current
                    end("Cambió la ruta de audio. Comprueba los dispositivos y vuelve a intentarlo.")
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
        }
    }
}
