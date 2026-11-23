import AVFoundation

struct SpanishVoice: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let male: Bool

    var title: String {
        male ? "\(name) · \(language) · masculina" : "\(name) · \(language)"
    }
}

@MainActor
final class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate {
    private var synthesizer: AVSpeechSynthesizer?
    private var utteranceID: ObjectIdentifier?
    private var completion: ((Bool) -> Void)?

    func voices() -> [SpanishVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es-") }
            .map { SpanishVoice(id: $0.identifier, name: $0.name, language: $0.language, male: $0.gender == .male) }
            .sorted {
                if $0.male != $1.male { return $0.male }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func speak(_ text: String, settings: AssistantSettings, completion: @escaping (Bool) -> Void) throws {
        let locale = settings.language.rawValue
        let voices = voices()
        let preferred = voices.first { $0.id == settings.voiceID }
            ?? voices.first { $0.language == locale && $0.male }
            ?? voices.first { $0.male }
        guard let voice = preferred.flatMap({ AVSpeechSynthesisVoice(identifier: $0.id) })
            ?? AVSpeechSynthesisVoice(language: locale)
            ?? AVSpeechSynthesisVoice(language: "es-ES"),
            voice.language.hasPrefix("es-") else { throw AssistantError.noSpanishVoice }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Float(settings.speechRate)
        utteranceID = ObjectIdentifier(utterance)
        self.completion = completion
        let synthesizer = self.synthesizer ?? makeSynthesizer()
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
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
