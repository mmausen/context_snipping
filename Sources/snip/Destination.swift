import Foundation

/// Ein Ablageort für eine gesicherte Sammlung.
///
/// Im Prototyp gibt es genau einen ("Inbox"). Die Abstraktion steht trotzdem
/// schon, weil beim Sichern später zwischen mehreren Zielen gewählt werden soll –
/// dann kommt ein Picker davor, statt dass hier umgebaut werden muss.
struct Destination {
    let id: String
    let name: String
    let root: URL
    let fileName: String

    var file: URL { root.appendingPathComponent(fileName) }
    var assetsFolder: URL { root.appendingPathComponent("assets") }
}

enum Destinations {
    /// Überschreibbar per `defaults write io.moux.snip SnipRoot -string "/pfad"`.
    static var root: URL {
        if let custom = UserDefaults.standard.string(forKey: "SnipRoot"), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/HYUX/snip/snips")
    }

    static var inbox: Destination {
        Destination(id: "inbox", name: "Inbox", root: root, fileName: "inbox.md")
    }

    static var all: [Destination] { [inbox] }

    /// Wohin die nächste Sammlung geht. Später vom Picker gesetzt.
    static var selected: Destination = inbox
}

enum SnipWriter {

    struct Result {
        let file: URL
        let count: Int
    }

    /// Hängt die Sammlung als einen Block an die Ziel-Datei an.
    /// Bilder landen als PNG in `assets/` und werden relativ verlinkt.
    static func append(_ session: Session, to destination: Destination) throws -> Result {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.root, withIntermediateDirectories: true)

        let hasImages = session.snips.contains { if case .image = $0.payload { return true }; return false }
        if hasImages {
            try fileManager.createDirectory(at: destination.assetsFolder, withIntermediateDirectories: true)
        }

        var block = "\n## \(headerFormatter.string(from: session.startedAt)) · \(session.count) \(session.count == 1 ? "Snip" : "Snips")\n"

        for (index, snip) in session.snips.enumerated() {
            block += "\n**\(snip.kindLabel)** · \(snip.sourceApp) · \(timeFormatter.string(from: snip.date))\n\n"

            switch snip.payload {
            case .text(let text):
                block += quoted(text) + "\n"

            case .image(let data):
                let name = "\(stampFormatter.string(from: snip.date))-\(index + 1).png"
                try data.write(to: destination.assetsFolder.appendingPathComponent(name))
                block += "![Snip](assets/\(name))\n"
            }
        }

        block += "\n---\n"

        try appendString(block, to: destination.file)
        return Result(file: destination.file, count: session.count)
    }

    // MARK: - Details

    private static func quoted(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
    }

    private static func appendString(_ string: String, to url: URL) throws {
        let data = Data(string.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            let header = Data("# Snips\n".utf8)
            try (header + data).write(to: url)
        }
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
