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
    static let rateRange = 0.35...0.60
    static let pitchRange = 0.85...1.12
    static let volumeRange = 0.0...1.0

    var language: SpanishLocale = .mexico
    var voiceID = ""
    var speechRate = 0.46
    var speechPitch = 0.93
    var speechVolume = 0.90
    var preferBluetooth = true
    var usePhoneSpeaker = true
    var offlineOnly = false

    init(defaults: UserDefaults) {
        language = SpanishLocale(rawValue: defaults.string(forKey: "language") ?? "") ?? .mexico
        voiceID = defaults.string(forKey: "voiceID") ?? ""
        speechRate = Self.savedValue("speechRate", defaults, Self.rateRange, fallback: speechRate)
        speechPitch = Self.savedValue("speechPitch", defaults, Self.pitchRange, fallback: speechPitch)
        speechVolume = Self.savedValue("speechVolume", defaults, Self.volumeRange, fallback: speechVolume)
        preferBluetooth = defaults.object(forKey: "preferBluetooth") as? Bool ?? true
        usePhoneSpeaker = defaults.object(forKey: "usePhoneSpeaker") as? Bool ?? true
        offlineOnly = defaults.bool(forKey: "offlineOnly")
    }

    func save(to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: "language")
        defaults.set(voiceID, forKey: "voiceID")
        defaults.set(speechRate, forKey: "speechRate")
        defaults.set(speechPitch, forKey: "speechPitch")
        defaults.set(speechVolume, forKey: "speechVolume")
        defaults.set(preferBluetooth, forKey: "preferBluetooth")
        defaults.set(usePhoneSpeaker, forKey: "usePhoneSpeaker")
        defaults.set(offlineOnly, forKey: "offlineOnly")
    }

    private static func savedValue(_ key: String, _ defaults: UserDefaults, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard let value = defaults.object(forKey: key) as? Double, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
