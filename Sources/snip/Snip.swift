import AppKit

/// Ein einzelner erfasster Happen.
struct Snip {
    enum Payload {
        case text(String)
        case image(Data) // immer PNG
    }

    let payload: Payload
    let sourceApp: String
    let date: Date

    var kindLabel: String {
        switch payload {
        case .text: return "Text"
        case .image: return "Bild"
        }
    }

    /// Kurzvorschau fürs HUD.
    var preview: String {
        switch payload {
        case .text(let string):
            let flat = string
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return flat.count > 42 ? String(flat.prefix(42)) + "…" : flat
        case .image(let data):
            return "Bild · \(data.count / 1024) KB"
        }
    }
}

/// Der offene Sammelstapel. Lebt nur zwischen „Sammlung starten" und „sichern".
final class Session {
    let startedAt = Date()
    private(set) var snips: [Snip] = []

    var count: Int { snips.count }
    var isEmpty: Bool { snips.isEmpty }

    func add(_ snip: Snip) {
        snips.append(snip)
    }
}
