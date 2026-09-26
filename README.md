# Marqet

iOS-Einkaufsliste auf Basis von Apple Erinnerungen, nach Läden sortiert.
Konzept: [docs/KONZEPT.md](docs/KONZEPT.md) · Markt & Angebote: [docs/MARKTANALYSE.md](docs/MARKTANALYSE.md)

## Voraussetzungen

- Xcode 27, iOS 26 SDK+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```bash
xcodegen generate
open Marqet.xcodeproj
```

`project.yml` ist die Quelle der Wahrheit für das Xcode-Projekt. Nach Änderungen daran `xcodegen generate` erneut ausführen.

## Struktur

| Pfad | Inhalt |
|---|---|
| `Marqet/` | App-Target (SwiftUI): `App/` (Einstieg, `AppModel`), `Features/`, `DesignSystem/`, `Resources/` |
| `Packages/MarqetKit/Sources/MarqetCore` | Reine Domänenlogik, nur Foundation: Marker-Format, Normalisierung, Laden-Erkennung, Katalog (`Resources/StoreCatalog.json`), Cards + Laden-Lebenszyklus (`CardBuilder`), Mehrfach-Ansicht (`SpreadLayout`) |
| `Packages/MarqetKit/Sources/MarqetPersistence` | SwiftData-Speicher der eigenen Läden (`StoreRepository`), CloudKit-kompatibel |
| `Packages/MarqetKit/Sources/MarqetReminders` | `ReminderGateway`-Protokoll, `EventKitGateway` (Actor), `InMemoryReminderGateway` für Tests und Previews |
| `MarqetTests/` | App-gehostete Integrationstests gegen echtes EventKit |

## Tests

Domänen- und Gateway-Tests laufen schnell auf dem Mac, ohne Simulator:

```bash
cd Packages/MarqetKit && swift test
```

EventKit-Integrationstests laufen im Simulator. Sie brauchen den Erinnerungen-Zugriff für die App (einmalig pro Simulator, nach der ersten Installation):

```bash
xcrun simctl privacy booted grant reminders app.marqet.Marqet
xcodebuild -project Marqet.xcodeproj -scheme Marqet -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Ohne diese Freigabe werden die Integrationstests übersprungen.

## Demo-Daten

In Debug-Builds startet die App mit dem Startparameter `-demo` mit Beispieldaten im Speicher, ohne Erinnerungen-Zugriff (z. B. für Screenshots oder das iPad):

```bash
xcrun simctl launch booted app.marqet.Marqet -demo
```

## Stand

- **M1 – Fundament** ✅: Marker, Laden-Erkennung, Katalog, EventKit-Gateway, Listenauswahl, Berechtigungen.
- **M2 – Hauptscreen** ✅: Card-Pager mit Laden-Cards in Markenfarbe; 1–4 Cards nebeneinander je nach Breite (iPad; iPhone Duo mit Falz-Ausrichtung, noch nicht auf dem Duo-Innendisplay gemessen); Laden-Lebenszyklus (geplant / leer eingekauft / ausgeblendet); Card „Weitere Läden“ mit Katalog-Vorschlägen und „Mehrere planen“; Laden hinzufügen (Katalog oder eigener Laden); Serien-Eingabe mit Laden-Chips; Abhaken mit 1,5 s Rückgängig; Erledigte anzeigen und „nochmal kaufen“; Laden ändern, Umbenennen, Löschen; Items per Drag zwischen Cards verschieben; SwiftData-Speicher der Läden.

Nächster Schritt: **M3 – Kategorien** (Abschnitte in den Cards) bzw. der Duo-Spike.
