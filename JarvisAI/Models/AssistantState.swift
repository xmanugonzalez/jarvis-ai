import Foundation

enum AssistantState: Equatable {
    case ready, preparing, listening, processing, speaking, recording, playing, checking

    var title: String {
        switch self {
        case .ready: "En espera"
        case .preparing: "Preparando audio"
        case .listening: "Escuchando"
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
        case .listening, .recording: "waveform"
        case .speaking, .playing: "speaker.wave.2"
        }
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
    case speechUnavailable, offlineUnavailable, noInput, routeUnavailable
    case recordingFailed, playbackFailed, noOutput, noSpanishVoice

    var errorDescription: String? {
        switch self {
        case .microphonePermission: "Permite el micrófono en Ajustes para capturar tu voz."
        case .speechPermission: "Permite el reconocimiento de voz en Ajustes para transcribir el audio."
        case .speechRestricted: "El reconocimiento de voz está restringido en este iPhone."
        case .speechUnavailable: "El reconocimiento no está disponible para este idioma. Comprueba la conexión o elige otra variante de español."
        case .offlineUnavailable: "Este idioma no admite reconocimiento local en este iPhone. Cambia de idioma o desactiva «Solo sin conexión»."
        case .noInput: "iOS no proporciona una entrada de audio en la ruta actual."
        case .routeUnavailable: "iOS no activó la entrada y salida manos libres. Comprueba el Bluetooth y vuelve a intentarlo."
        case .recordingFailed: "No se pudo guardar la grabación de prueba. Vuelve a grabar."
        case .playbackFailed: "No se pudo reproducir la grabación de prueba. Comprueba la ruta de audio."
        case .noOutput: "iOS no proporciona una salida de audio en la ruta actual."
        case .noSpanishVoice: "iOS no ofrece una voz en español. Instala una voz en los Ajustes del iPhone y vuelve a intentarlo."
        }
    }
}
