import Foundation

@main
enum HandsFreeTests {
    static func main() {
        let turn = HandsFreeTurn(startLimit: 8, silenceLimit: 2.25)
        precondition(turn.decision(elapsed: 4, lastSpeech: 2.5, hasText: true) == .keepListening)
        precondition(turn.decision(elapsed: 5, lastSpeech: 2.5, hasText: true) == .silence)
        precondition(turn.decision(elapsed: 7, lastSpeech: nil, hasText: false) == .keepListening)
        precondition(turn.decision(elapsed: 8, lastSpeech: nil, hasText: false) == .noSpeech)
        precondition(turn.decision(elapsed: 8, lastSpeech: 7.9, hasText: false) == .keepListening)
        precondition(turn.decision(elapsed: 25, lastSpeech: 24.9, hasText: true) == .timeLimit)
        precondition(turn.decision(elapsed: 25, lastSpeech: 24.9, hasText: false) == .noSpeech)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 8, minute: 30))!
        precondition(LocalResponses.recognizedReply(to: "¿Qué hora es?", now: now, calendar: calendar) == "Son las ocho y treinta.")
        precondition(LocalResponses.recognizedReply(to: "¿Y qué fecha es hoy?", now: now, calendar: calendar, followUp: true) == "Hoy es domingo, 22 de noviembre.")
        precondition(LocalResponses.recognizedReply(to: "¿Qué hora es?", followUp: true) == nil)
        precondition(LocalResponses.recognizedReply(to: "Y nos quedamos allí", followUp: true) == nil)
        print("OK: pausas, silencio, límites y filtro de continuación")
    }
}
