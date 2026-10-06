# context_snipping

> ⚠️ **Work in Progress** – ganz früher Prototyp, nicht für den Alltag gedacht.

Beim Arbeiten verteilt sich Kontext über viele Apps: ein Absatz im Browser, eine Zeile im Code, ein Bild in einem PDF, eine Notiz im Chat. **context_snipping** ist eine kleine macOS-Menüleisten-App, die genau das einsammelt – app-übergreifend, per Tastenkombination, ohne den Arbeitsfluss zu unterbrechen – und das Gesammelte einem bestimmten Kontext zuordnet.

## Stand heute

- Systemweite Tastenkombinationen öffnen eine Sammlung, greifen die aktuelle Auswahl und sichern sie
- Erfasst Text und kopierte Bilder aus nahezu jeder App
- Während einer offenen Sammlung wird auch normales ⌘C mitgeschnitten
- Ablage als fortlaufende Markdown-Datei, Bilder als PNG daneben

| Tasten | Wirkung |
|---|---|
| ⌥⌘S | Sammlung öffnen |
| ⌥⌘C | Auswahl greifen |
| ⌥⌘⏎ | Sammlung sichern |
| ⌥⌘. | Sammlung verwerfen |

## Angedacht

- **Mehrere Kontexte** – beim Sichern wählen, zu welchem Projekt oder Thema das Gesammelte gehört
- **Annotationen** – Snips direkt beim Erfassen kommentieren oder einordnen
- Bereichs-Screenshots für Inhalte, die sich nicht kopieren lassen
- Trackpad-Geste als Auslöser
- …

## Ausprobieren

macOS 14+, Xcode bzw. Swift-Toolchain.

```bash
./build.sh && open Snip.app
```

Beim ersten Start braucht die App die Freigabe unter *Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen*, sonst kann sie keine Auswahl greifen.
