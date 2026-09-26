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

In Debug-Builds startet die App mit dem Startparameter `-demo` mit Beispieldaten im Speicher, ohne Erinnerungen-Zugriff (z. B. für Screenshots oder das iPad). `-pro` schaltet Marqet Pro ein, `-triage` öffnet direkt das Zuordnen:

```bash
xcrun simctl launch booted app.marqet.Marqet -demo -pro -triage
```

Marqet Pro lässt sich bis zur StoreKit-Anbindung (M7) nur in Debug-Builds über Einstellungen › Entwicklung einschalten.

## Stand

| Meilenstein | Status |
|---|---|
| **M1 Fundament** | ✅ Marker, Laden-Erkennung, Katalog, EventKit-Gateway, Listenauswahl, Berechtigungen |
| **M2 Hauptscreen** | ✅ Laden-Cards in Markenfarbe, 1–4 Cards je Breite (iPad, Duo-Falz vorbereitet), Lebenszyklus, „Weitere Läden“, Laden hinzufügen, Serien-Eingabe mit Laden-Chips, Abhaken mit Rückgängig, Drag zwischen Cards |
| **M3 Kategorien** | ✅ Wörterbuch DE/EN/AT/CH (≈ 1.000 Begriffe, Komposita, Ausnahmen), Abschnitte in Lebensmittel-Läden, „Kategorie ändern“ (wird gelernt), „Abschnitte sortieren“ pro Laden. Goldset 293 Einträge: 100 % |
| **M4 Zuordnen** | ✅ Nachfrage bei neuen Einträgen, Zuordnen-Screen Einzeln/Board (Tippen, Ziehen, VoiceOver-Aktionen), gelernte Vorschläge (Free), Überspringen, Rückgängig, „Alle Vorschläge übernehmen“, Zusammenfassung mit Pro-Hinweis; auf iPad/Duo zweiseitig |
| **M5 Onboarding & Einstellungen** | ✅ Onboarding (Willkommen, Zugriff, Liste, Läden, Siri-Tipp → direkt Zuordnen), Einstellungen, Läden verwalten (sortieren, umbenennen mit Marker-Umschreibung, Farbe/Symbol/Art, löschen) |
| **M6 Pro-Intelligenz** | ✅ Auto-Zuordnung mit Rückgängig, Apple Intelligence (Foundation Models, geführte Generierung) für Läden und Kategorien, Ladenart-Heuristik als Fallback, Laufweg lernen (Kategorien und Einträge pro Laden) |
| M7 Kauf | offen – bis dahin Pro nur über den Debug-Schalter |
| M8 Launch-Reife | offen |

**Tests:** 85 im Paket (`swift test`), 16 in der App (AppModel-Abläufe M2–M6 und EventKit).

**Bekannte Lücken:** Löschen ohne Rückgängig; Items innerhalb eines Abschnitts nicht per Drag sortierbar (Free: alphabetisch, Pro: Laufweg); Kategorie-Korrektur per Menü statt Ziehen zwischen Abschnitten; Duo-Innendisplay und `ArrangementView` (ab iOS 27.1) nicht im Simulator geprüft; mehrere iPad-Fenster aus; Wörterbuch ≈ 1.000 statt 2.500 Begriffe.
