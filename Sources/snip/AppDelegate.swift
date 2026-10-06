import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var session: Session?
    private var watcher: PasteboardWatcher!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpHotKeys()

        watcher = PasteboardWatcher { [weak self] snip in
            self?.collect(snip, viaSystemCopy: true)
        }

        requestAccessibilityIfNeeded()
        HUD.shared.show("snip bereit", detail: "⌥⌘S startet eine Sammlung")
    }

    // MARK: - Hotkeys

    private func setUpHotKeys() {
        let optCmd = Mod.opt | Mod.cmd
        hotKeys = [
            HotKey(keyCode: Key.s, modifiers: optCmd) { [weak self] in self?.startSession() },
            HotKey(keyCode: Key.c, modifiers: optCmd) { [weak self] in self?.grab() },
            HotKey(keyCode: Key.ret, modifiers: optCmd) { [weak self] in self?.saveSession() },
            HotKey(keyCode: Key.period, modifiers: optCmd) { [weak self] in self?.discardSession() },
        ].compactMap { $0 }
    }

    // MARK: - Ablauf

    @objc private func startSession() {
        guard session == nil else {
            HUD.shared.show("Sammlung läuft", detail: statusDetail())
            return
        }
        session = Session()
        watcher.start()
        updateStatusItem()
        HUD.shared.show("Sammlung offen", detail: "⌘C sammelt · ⌥⌘⏎ sichert")
    }

    /// Greift die aktuelle Auswahl aktiv ab. Ohne offene Sammlung wird eine
    /// gestartet – bequemer, als erst ins Leere zu greifen.
    @objc private func grab() {
        if session == nil { startSession() }
        Capture.grabSelection { [weak self] snip in
            guard let self else { return }
            self.watcher.rebaseline()
            guard let snip else {
                HUD.shared.show("Nichts gefunden", detail: "Auswahl leer oder App kopiert nicht")
                return
            }
            self.collect(snip, viaSystemCopy: false)
        }
    }

    private func collect(_ snip: Snip, viaSystemCopy: Bool) {
        guard let session else { return }
        session.add(snip)
        updateStatusItem()
        HUD.shared.show("Snip \(session.count) · \(snip.kindLabel)", detail: snip.preview)
    }

    @objc private func saveSession() {
        guard let session else {
            HUD.shared.show("Keine Sammlung offen", detail: "⌥⌘S startet eine")
            return
        }
        guard !session.isEmpty else {
            discardSession()
            return
        }

        let destination = Destinations.selected
        do {
            let result = try SnipWriter.append(session, to: destination)
            HUD.shared.show(
                "\(result.count) \(result.count == 1 ? "Snip" : "Snips") gesichert",
                detail: "→ \(destination.name) · \(destination.fileName)"
            )
        } catch {
            HUD.shared.show("Sichern fehlgeschlagen", detail: error.localizedDescription, duration: 3)
            NSLog("snip: Sichern fehlgeschlagen – \(error)")
        }

        closeSession()
    }

    @objc private func discardSession() {
        guard session != nil else { return }
        closeSession()
        HUD.shared.show("Sammlung verworfen")
    }

    private func closeSession() {
        session = nil
        watcher.stop()
        updateStatusItem()
    }

    private func statusDetail() -> String {
        guard let session else { return "" }
        return session.isEmpty ? "noch nichts gesammelt" : "\(session.count) gesammelt"
    }

    // MARK: - Menüleiste

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let open = session != nil
        button.image = NSImage(
            systemSymbolName: open ? "scissors.circle.fill" : "scissors",
            accessibilityDescription: "snip"
        )
        button.title = open ? " \(session!.count)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let session {
            menu.addItem(disabledItem("Sammlung offen · \(session.count) Snips"))
            menu.addItem(item("Auswahl greifen", #selector(grab), "c"))
            menu.addItem(item("Sichern → \(Destinations.selected.name)", #selector(saveSession), "\r"))
            menu.addItem(item("Verwerfen", #selector(discardSession), "."))
        } else {
            menu.addItem(disabledItem("Keine Sammlung offen"))
            menu.addItem(item("Sammlung starten", #selector(startSession), "s"))
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Ziel: \(Destinations.selected.name)"))
        menu.addItem(item("Ordner öffnen", #selector(openFolder), ""))

        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(item("⚠︎ Bedienungshilfen freigeben…", #selector(openAccessibilitySettings), ""))
        }
        menu.addItem(item("snip beenden", #selector(quit), "q"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : [.option, .command]
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openFolder() {
        let root = Destinations.selected.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Berechtigung

    /// Ohne Bedienungshilfen-Freigabe kann kein synthetisches ⌘C verschickt werden.
    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSLog("snip: Bedienungshilfen noch nicht freigegeben.")
        }
    }
}
