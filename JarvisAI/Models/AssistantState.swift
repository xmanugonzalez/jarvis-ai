import Foundation

enum AssistantState: Equatable {
    case ready, preparing, waitingWake, cue, listening, processing, speaking, recording, playing, checking

    var title: String {
        switch self {
        case .ready: "En espera"
        case .preparing: "Preparando audio"
        case .waitingWake: "Esperando «Jarvis»"
        case .cue: "Confirmando activación"
        case .listening: "Escuchando instrucción"
        case .processing: "Procesando voz"
        case .speaking: "Respondiendo"
        case .recording: "Grabando prueba"
        case .playing: "Reproduciendo prueba"
        case .checking: "Comprobando ruta"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "mic"
        case .preparing, .processing, .checking: "ellipsis"
        case .waitingWake: "ear"
        case .cue: "speaker.wave.1"
        case .listening, .recording: "waveform"
        case .speaking, .playing: "speaker.wave.2"
        }
    }
}

struct HandsFreeTurn {
    enum End: Equatable { case keepListening, silence, noSpeech, timeLimit }

    let startLimit: Double
    let silenceLimit: Double
    static let maximumSeconds = 25.0

    func decision(elapsed: Double, lastSpeech: Double?, hasText: Bool) -> End {
        if elapsed >= Self.maximumSeconds { return hasText ? .timeLimit : .noSpeech }
        if let lastSpeech, elapsed - lastSpeech >= silenceLimit, hasText { return .silence }
        if !hasText && (lastSpeech == nil || elapsed - (lastSpeech ?? 0) >= silenceLimit),
           elapsed >= startLimit { return .noSpeech }
        return .keepListening
    }
}

struct AudioRoute: Equatable {
    var inputs: [String] = []
    var outputs: [String] = []
    var availableHFP: [String] = []
    var usesHFP = false
    var usesOtherBluetooth = false
    var verified = false
    var signature: [String] = []
}

struct AssistantNotice: Equatable {
    let message: String
    var openSettings = false
}

enum AssistantError: LocalizedError, Equatable {
    case microphonePermission, speechPermission, speechRestricted
    case speechUnavailable, unsupportedSpeechLanguage, offlineUnavailable, noInput, routeUnavailable
    case captureChanged, speechTimedOut
    case recordingFailed, playbackFailed, noOutput, wakeUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermission: "Permite el micrófono en Ajustes para capturar tu voz."
        case .speechPermission: "Permite el reconocimiento de voz en Ajustes para transcribir el audio."
        case .speechRestricted: "El reconocimiento de voz está restringido en este iPhone."
        case .speechUnavailable: "El reconocimiento no está disponible para este idioma. Comprueba la conexión o elige otra variante de español."
        case .unsupportedSpeechLanguage: "Apple Speech no admite el idioma seleccionado en este iPhone. Elige otra variante de español."
        case .captureChanged: "La configuración del micrófono cambió. Comprueba la ruta y vuelve a escuchar."
        case .speechTimedOut: "Apple Speech tardó demasiado en cerrar la transcripción. Vuelve a intentarlo."
        case .offlineUnavailable: "Este idioma no admite reconocimiento local en este iPhone. Cambia de idioma o desactiva «Solo sin conexión»."
        case .noInput: "iOS no proporciona una entrada de audio en la ruta actual."
        case .routeUnavailable: "iOS no activó la entrada y salida manos libres. Comprueba el Bluetooth y vuelve a intentarlo."
        case .recordingFailed: "No se pudo guardar la grabación de prueba. Vuelve a grabar."
        case .playbackFailed: "No se pudo reproducir la grabación de prueba. Comprueba la ruta de audio."
        case .noOutput: "iOS no proporciona una salida de audio en la ruta actual."
        case .wakeUnavailable: "El detector de «Jarvis» no está disponible. Vuelve a instalar el IPA desde SideStore."
        }
    }
}
