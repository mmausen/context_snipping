import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Holt die aktuelle Auswahl aus *irgendeiner* App, indem ein synthetisches ⌘C
/// verschickt und anschließend das Pasteboard ausgelesen wird. Der vorherige
/// Clipboard-Inhalt wird danach wiederhergestellt.
///
/// Das ist der Weg, der in nahezu allen Apps funktioniert – nativ, Electron,
/// Browser, PDF. Die Alternative (`AXSelectedText` über die Accessibility-API)
/// wäre sauberer, liefert aber nur Text und in vielen Apps gar nichts.
enum Capture {

    /// Solange gesetzt, ignoriert der `PasteboardWatcher` Änderungen –
    /// sonst würde er unseren eigenen Kunstgriff als Nutzer-Kopie mitschneiden.
    private(set) static var isGrabbing = false

    static func grabSelection(completion: @escaping (Snip?) -> Void) {
        let sourceApp = frontmostAppName()
        isGrabbing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let pasteboard = NSPasteboard.general
            let backup = snapshot(pasteboard)
            let changeCountBefore = pasteboard.changeCount

            // Der Hotkey feuert, während ⌥⌘ noch physisch gedrückt sind. Würden
            // wir jetzt schon senden, käme in der Ziel-App ⌥⌘C an statt ⌘C.
            waitForModifierRelease()
            postCommandC()

            let didChange = waitForPasteboardChange(pasteboard, from: changeCountBefore)
            let snip = didChange ? read(pasteboard, sourceApp: sourceApp) : nil

            restore(backup, to: pasteboard)

            DispatchQueue.main.async {
                isGrabbing = false
                completion(snip)
            }
        }
    }

    /// Liest, was gerade im Pasteboard liegt – ohne etwas zu verändern.
    /// Wird vom `PasteboardWatcher` benutzt, wenn der Nutzer selbst ⌘C drückt.
    static func readCurrentPasteboard() -> Snip? {
        read(NSPasteboard.general, sourceApp: frontmostAppName())
    }

    static func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unbekannt"
    }

    // MARK: - Pasteboard lesen

    private static func read(_ pasteboard: NSPasteboard, sourceApp: String) -> Snip? {
        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pngData(from: pasteboard)
        let now = Date()

        // Ein aus dem Browser kopiertes Bild bringt oft zusätzlich seine URL als
        // Text mit. In dem Fall ist das Bild gemeint, nicht die URL.
        if let image, text == nil || text!.isEmpty || isBareURL(text!) {
            return Snip(payload: .image(image), sourceApp: sourceApp, date: now)
        }
        if let text, !text.isEmpty {
            return Snip(payload: .text(text), sourceApp: sourceApp, date: now)
        }
        if let image {
            return Snip(payload: .image(image), sourceApp: sourceApp, date: now)
        }
        return nil
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    private static func isBareURL(_ string: String) -> Bool {
        guard !string.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        return string.hasPrefix("http://") || string.hasPrefix("https://")
    }

    // MARK: - Clipboard sichern und zurückgeben

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.compactMap { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        } ?? []
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    // MARK: - Tastatur-Synthese

    private static func postCommandC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalKeyboardEvents, .permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let key = CGKeyCode(kVK_ANSI_C)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(12_000)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func waitForModifierRelease(timeout: TimeInterval = 0.4) {
        let watched: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(watched).isEmpty { return }
            usleep(15_000)
        }
    }

    private static func waitForPasteboardChange(
        _ pasteboard: NSPasteboard,
        from changeCountBefore: Int,
        timeout: TimeInterval = 0.6
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCountBefore {
                usleep(30_000) // der Ziel-App Zeit lassen, alle Typen zu schreiben
                return true
            }
            usleep(15_000)
        }
        return false
    }
}

/// Schneidet ganz normale ⌘C-Kopien mit, solange eine Sammlung offen ist.
/// So muss man während einer Session keinen Extra-Hotkey lernen.
final class PasteboardWatcher {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let onCopy: (Snip) -> Void

    init(onCopy: @escaping (Snip) -> Void) {
        self.onCopy = onCopy
    }

    func start() {
        rebaseline()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Nach einem eigenen Grab aufrufen, damit das Zurückschreiben des
    /// Clipboards nicht als neue Nutzer-Kopie gilt.
    func rebaseline() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func tick() {
        guard !Capture.isGrabbing else {
            rebaseline()
            return
        }
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if let snip = Capture.readCurrentPasteboard() {
            onCopy(snip)
        }
    }
}
