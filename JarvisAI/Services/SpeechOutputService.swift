import AVFoundation

enum VoiceQuality: Int, CaseIterable {
    case premium = 3
    case enhanced = 2
    case standard = 1
    case unknown = 0

    init(_ quality: AVSpeechSynthesisVoiceQuality) {
        switch quality {
        case .premium: self = .premium
        case .enhanced: self = .enhanced
        case .default: self = .standard
        @unknown default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .premium: "Premium"
        case .enhanced: "Mejorada (Enhanced)"
        case .standard: "Predeterminada (Default)"
        case .unknown: "Calidad sin clasificar"
        }
    }
}

struct SpanishVoice: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let male: Bool
    let quality: VoiceQuality

    static func languageTitle(_ code: String) -> String {
        Locale(identifier: "es").localizedString(forIdentifier: code) ?? code
    }
}

@MainActor
protocol SpeechSynthesisProvider {
    func voices() -> [SpanishVoice]
    func speak(_ text: String, settings: AssistantSettings, previewVoiceID: String?, completion: @escaping (Bool) -> Void) throws
    func cancel()
    func reset()
}

@MainActor
final class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate, SpeechSynthesisProvider {
    private var synthesizer: AVSpeechSynthesizer?
    private var utteranceID: ObjectIdentifier?
    private var completion: ((Bool) -> Void)?

    func voices() -> [SpanishVoice] {
        availableVoices().map {
            SpanishVoice(id: $0.identifier, name: $0.name, language: $0.language,
                         male: $0.gender == .male, quality: VoiceQuality($0.quality))
        }
    }

    func speak(_ text: String, settings: AssistantSettings, previewVoiceID: String?, completion: @escaping (Bool) -> Void) throws {
        let locale = settings.language.rawValue
        let voices = availableVoices()
        let selected = voices.first { $0.identifier == (previewVoiceID ?? settings.voiceID) }
        if let previewVoiceID, !previewVoiceID.isEmpty, selected == nil {
            throw AssistantError.previewVoiceUnavailable
        }
        let automatic = voices.sorted {
            let left = ($0.gender == .male ? 1 : 0, VoiceQuality($0.quality).rawValue, $0.language == locale ? 1 : 0)
            let right = ($1.gender == .male ? 1 : 0, VoiceQuality($1.quality).rawValue, $1.language == locale ? 1 : 0)
            if left != right { return left > right }
            return $0.identifier < $1.identifier
        }.first
        guard let voice = selected ?? automatic else { throw AssistantError.noSpanishVoice }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(settings.speechRate)
        utterance.pitchMultiplier = Float(settings.speechPitch)
        utterance.volume = Float(settings.speechVolume)
        utteranceID = ObjectIdentifier(utterance)
        self.completion = completion
        let synthesizer = self.synthesizer ?? makeSynthesizer()
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
    }

    private func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "es" || $0.language.hasPrefix("es-") }
    }

    func cancel() {
        utteranceID = nil
        completion = nil
        synthesizer?.stopSpeaking(at: .immediate)
    }

    func reset() {
        cancel()
        synthesizer = nil
    }

    private func makeSynthesizer() -> AVSpeechSynthesizer {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        return synthesizer
    }

    private func complete(_ identifier: ObjectIdentifier, success: Bool) {
        guard utteranceID == identifier else { return }
        let callback = completion
        utteranceID = nil
        completion = nil
        callback?(success)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in self.complete(identifier, success: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in self.complete(identifier, success: false) }
    }
}
