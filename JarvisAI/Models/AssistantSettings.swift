import Foundation

enum SpanishLocale: String, CaseIterable, Identifiable {
    case mexico = "es-MX"
    case spain = "es-ES"
    case unitedStates = "es-US"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mexico: "Español (México)"
        case .spain: "Español (España)"
        case .unitedStates: "Español (Estados Unidos)"
        }
    }
}

struct AssistantSettings {
    var language: SpanishLocale = .mexico
    var voiceID = ""
    var speechRate = 0.48
    var preferBluetooth = true
    var usePhoneSpeaker = true
    var offlineOnly = false

    init(defaults: UserDefaults) {
        language = SpanishLocale(rawValue: defaults.string(forKey: "language") ?? "") ?? .mexico
        voiceID = defaults.string(forKey: "voiceID") ?? ""
        if let rate = defaults.object(forKey: "speechRate") as? Double {
            speechRate = min(max(rate, 0.35), 0.60)
        }
        preferBluetooth = defaults.object(forKey: "preferBluetooth") as? Bool ?? true
        usePhoneSpeaker = defaults.object(forKey: "usePhoneSpeaker") as? Bool ?? true
        offlineOnly = defaults.bool(forKey: "offlineOnly")
    }

    func save(to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: "language")
        defaults.set(voiceID, forKey: "voiceID")
        defaults.set(speechRate, forKey: "speechRate")
        defaults.set(preferBluetooth, forKey: "preferBluetooth")
        defaults.set(usePhoneSpeaker, forKey: "usePhoneSpeaker")
        defaults.set(offlineOnly, forKey: "offlineOnly")
    }
}
