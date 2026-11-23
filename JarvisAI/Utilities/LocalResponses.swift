import Foundation

enum LocalResponses {
    static func reply(to transcript: String) -> String {
        recognizedReply(to: transcript) ?? "Le he escuchado, señor."
    }

    static func recognizedReply(to transcript: String, now: Date = Date(), calendar: Calendar = .current,
                                followUp: Bool = false) -> String? {
        let words = transcript
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .split { !$0.isLetter && !$0.isNumber }
        let phrase = words.joined(separator: " ")
        if followUp && !phrase.hasPrefix("y ") && !phrase.hasPrefix("tambien ") { return nil }
        if phrase.contains("que hora es") || phrase.contains("dime la hora") {
            let hour = calendar.component(.hour, from: now) % 12
            let minute = calendar.component(.minute, from: now)
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "es")
            formatter.numberStyle = .spellOut
            let spokenHour = hour == 1 ? "una" : formatter.string(from: NSNumber(value: hour == 0 ? 12 : hour)) ?? "\(hour)"
            let spokenMinute = formatter.string(from: NSNumber(value: minute)) ?? "\(minute)"
            let suffix = minute == 0 ? "en punto" : "y \(spokenMinute)"
            return "\(hour == 1 ? "Es la" : "Son las") \(spokenHour) \(suffix)."
        }
        if phrase.contains("que fecha es") || phrase.contains("que dia es") || phrase.contains("dime la fecha") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEEE, d 'de' MMMM"
            return "Hoy es \(formatter.string(from: now))."
        }
        if followUp { return nil }
        if words.contains("hola") {
            return "A sus órdenes, señor."
        }
        if words.contains("gracias") {
            return "De nada, señor."
        }
        return nil
    }
}
