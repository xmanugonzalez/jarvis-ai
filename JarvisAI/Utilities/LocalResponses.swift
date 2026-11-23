import Foundation

enum LocalResponses {
    static func reply(to transcript: String) -> String {
        let words = transcript
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .split { !$0.isLetter && !$0.isNumber }
        if words.contains("hola") {
            return "A sus órdenes, señor."
        }
        if words.contains("gracias") {
            return "De nada, señor."
        }
        return "Le he escuchado, señor."
    }
}
