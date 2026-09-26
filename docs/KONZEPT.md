# Marqet – MVP-Konzept

Stand: 26.09.2026 (Rev. 3: iPhone Duo & iPad) · Status: M1 umgesetzt, als Nächstes M0-Duo-Spike + M2
Wettbewerb, Angebote-APIs und Langfrist-Strategie: [MARKTANALYSE.md](MARKTANALYSE.md) · iPhone Duo & iPad: [KONZEPT-DUO-IPAD.md](KONZEPT-DUO-IPAD.md)

> Marqet ist eine iOS-App, die die Einkaufsliste aus Apple Erinnerungen nach Läden sortiert.
> Items kommen wie gewohnt über Siri, die Erinnerungen-App oder Familienmitglieder rein.
> Marqet ordnet sie Läden zu und zeigt pro Laden eine große, wischbare Card.

---

## 1. Entscheidungslog

| # | Thema | Entscheidung |
|---|---|---|
| 1 | Speicherort der Zuordnung | **Notizfeld** der Erinnerung, Zeile `🛒 <Laden>` |
| 2 | Geteilte Listen | **Nice-to-have:** Zuordnung synct über die Notizen, Laden-Konfiguration pro Person |
| 3 | Laden-Modell | **Vordefinierte Ketten** (Katalog) + eigene Läden, ohne Logos |
| 4 | Zuordnen-UX | **Einzeln und Board** mit Umschalter |
| 5 | Zusätzliche Cards | **„Unsortiert“-Card vorne**, solange es unsortierte Items gibt |
| 6 | Intelligenz | **Lokales Lernen + Apple Intelligence** (Foundation Models) |
| 7 | Plattform | *Rev. 3:* **iPhone, iPhone Duo und iPad ab v1.0**, iOS 26+, Duo-Funktionen ab iOS 27.1 per `#available`, SwiftUI, Xcode 27 (SDK 27.1) |
| 8 | Geschäftsmodell | **Freemium + Einmalkauf** „Marqet Pro“ |
| 9 | Plus-Button | **Kontextabhängig:** neues Item gehört zum Laden der aktiven Card |
| 10 | Erledigte Items | **Wie Reminders:** Häkchen, nach ~1,5 s ausblenden, „Erledigte anzeigen“ |
| 11 | Zuordnen-Trigger | **Pro: Auto-Zuordnung** sicherer Items, danach Nachfrage für den Rest |
| 12 | Listen | **Eine** Erinnerungsliste, wechselbar in den Einstellungen |
| 13 | Sortierung in Card | *Rev. 2:* **Kategorie-Abschnitte** (wie Bring!/Reminders). **Laufweg lernt die Reihenfolge der Kategorien** pro Laden (Pro). Free: Standard-Reihenfolge, manuell anpassbar |
| 14 | Leere Läden | *Rev. 2:* **Lebenszyklus** statt Sofort-Ausblenden: vom Nutzer hinzugefügte (geplante) Läden bleiben, im Einkauf leer gewordene verschwinden erst nach der Einkaufssitzung (siehe 7.2) |
| 15 | Pro-Umfang | **Nur Intelligenz ist Pro:** Auto-Zuordnung, KI-Vorschläge, Laufweg |
| 16 | Free-Tier | Gelernte Vorschläge **hervorgehoben** (ein Tipp bestätigt) |
| 17 | Markt | **DACH**, Deutsch und Englisch |
| 18 | Design | **Native Liquid Glass + Laden-Farben** |
| 19 | Siri / App Intents | **v1.1**, im MVP reicht die Standard-Siri-Eingabe über Reminders |
| 20 | Analytics | **Keine.** Privacy-Label „Keine Daten erfasst“ |
| 21 | Kategorien | **v1.0:** eigene Kategorisierung (Wörterbuch DE/EN + Lernen aus Korrekturen, KI-Fallback in Pro). Apples Kategorien sind über EventKit nicht lesbar |
| 22 | Letzte Card | **v1.0:** „Weitere Läden“: alle ausgeblendeten Läden + „Laden hinzufügen“, Mehrfachauswahl zum Planen |
| 23 | Item für Laden ohne Card | **v1.0:** über die Card „Weitere Läden“, Long-Press auf den Plus-Button oder die Laden-Chipleiste in der Eingabe |
| 24 | Laden-Reihenfolge | **v1.0:** manuell. **v1.2:** zusätzlich nach Entfernung und „Smart“ (Artikel pro Anfahrtsminute) |
| 25 | Karte & Filialen | **v1.2** („Orte“): Datenmodell ist in v1.0 bereits vorbereitet |
| 26 | Routenplanung | **v1.3:** Einkaufsrunde mit optimaler Reihenfolge, Übergabe an Apple Maps |
| 28 | Spread-Modell | **v1.0:** Pager zeigt je nach Container-Breite 1–4 Cards. Duo innen: 2 Cards, Lücke exakt auf dem Falz |
| 29 | Anker | **v1.0:** Duo: aktive Card bleibt beim Aufklappen rechts, links erscheint die Vorgänger-Card bzw. „Weitere Läden“. iPad: aktive Card links |
| 30 | Plus-Button | **v1.0:** System-Toolbar-Item statt eigenem FAB (wird auf dem Duo senkrecht). Long Press = „Hinzufügen zu …“ |
| 31 | Große Displays | **v1.0:** Drag zwischen Cards, zweiseitiges Zuordnen, Sheets links, iPad-Kurzbefehle. **v1.1:** Küchenmodus (Tischhaltung), linke Seite anheften, Drag aus anderen Apps |
| 27 | Angebote | **v2.0**, nur über eine Publisher-Partnerschaft (ShopFully/Offerista oder Bonial). v1.1: Prospekt-Link pro Kette |

---

## 2. Produktprinzipien

1. **Erinnerungen ist die Quelle der Wahrheit.** Marqet hat kein eigenes Backend und keine eigene Item-Datenbank. Jedes Item ist ein `EKReminder`. Wer Marqet löscht, verliert keine Einträge.
2. **Zuordnen ist der Kern.** Die meisten Items kommen ohne Laden rein (Siri, Partner, Mac). Zuordnen muss in Sekunden erledigt sein und mit jeder Nutzung weniger Arbeit machen.
3. **Im Laden zählt nur eine Card.** Große Card, große Trefferflächen, einhändig bedienbar, sortiert nach Laufweg.
4. **Privat per Design.** Alles bleibt auf dem Gerät bzw. im iCloud-Konto des Nutzers, KI läuft on-device, kein Tracking.
5. **Kompatibel mit Menschen ohne Marqet.** Die Notiz `🛒 Aldi` ist auch in der Erinnerungen-App lesbar und manuell pflegbar.

---

## 3. Technische Rahmenbedingungen (EventKit)

| Verfügbar | Nicht verfügbar → Konsequenz |
|---|---|
| Listen (`EKCalendar`), Titel, `notes`, `isCompleted`, `completionDate`, `creationDate`, Fälligkeit, Priorität | **Tags, Abschnitte (auch Einkaufslisten-Kategorien), Unteraufgaben-Hierarchie, Flags, Bilder** → Zuordnung nur über `notes` |
| `EKEventStoreChanged`-Notification (App im Vordergrund) | **Kein Hintergrund-Push** → Refresh bei `scenePhase == .active` + bei Notification |
| Sync über iCloud inkl. geteilter Listen | **Keine manuelle Reihenfolge** → Sortierung verwaltet Marqet lokal |
| Voller Zugriff via `requestFullAccessToReminders()` | Das URL-Feld von Reminders ist über EventKit nicht zuverlässig nutzbar |

Weitere Punkte:
- `Info.plist`: `NSRemindersFullAccessUsageDescription` (lokalisiert DE/EN). Write-only-Zugriff reicht nicht.
- Unteraufgaben aus der Erinnerungen-App erscheinen in EventKit als normale Items. Das ist für den MVP akzeptiert.
- Wiederkehrende Erinnerungen verhalten sich normal (Abhaken erzeugt das nächste Vorkommen).
- Fälligkeiten und Alarme fasst Marqet nie an.

---

## 4. Das Marker-Format (Kernspezifikation)

### 4.1 Format

```
<freier Notiztext des Nutzers, optional, beliebig viele Zeilen>
🛒 <Ladenname>
```

- Präfix: `🛒` (U+1F6D2), optional gefolgt von Variation Selector U+FE0F, dann beliebig viel Whitespace, dann Ladenname.
- Regex (Zeilenweise, Unicode): `^\s*🛒️?\s*(\S.*?)\s*$`
- Das Emoji ist sprachneutral: DE- und EN-Nutzer in derselben geteilten Liste verstehen sich.

### 4.2 Lesen

1. Notizen zeilenweise durchsuchen, **die letzte passende Zeile gilt**.
2. Der Ladenname wird mit allen bekannten Läden verglichen (`name` + `aliases`), **case- und diakritik-insensitiv** („aldi sued“ = „Aldi Süd“).
3. Keine Übereinstimmung → Marqet legt automatisch einen **eigenen Laden** mit diesem Namen an (Herkunft `detected`, neutrale Farbe, Hinweis „Neu erkannt aus deiner Liste“). So kommen Läden aus geteilten Listen einfach an.
4. Der **Nutzertext** zur Anzeige sind die Notizen ohne alle Marker-Zeilen, getrimmt.

### 4.3 Schreiben

1. Vor dem Schreiben `reminder.refresh()`, um parallele Notiz-Änderungen nicht zu überschreiben.
2. **Alle** vorhandenen Marker-Zeilen entfernen, dann trailing Whitespace und Leerzeilen trimmen.
3. Zuordnen: `"\n🛒 <kanonischer Name>"` anhängen (bzw. nur `"🛒 <Name>"` bei leerer Notiz).
4. Zuordnung entfernen: Marker-Zeilen entfernen, bei leerem Ergebnis `notes = nil`.
5. Freitext bleibt **byte-genau** erhalten (Testfall-Pflicht).

### 4.4 Umbenennen und Löschen von Läden

- **Umbenennen:** Die Marker aller *offenen* Items dieses Ladens werden neu geschrieben, der alte Name wird als Alias behalten. So werden Geräte anderer Personen weiterhin erkannt.
- **Löschen:** Bestätigungsdialog „4 offene Items werden unsortiert“. Die Marker offener Items werden entfernt, erledigte bleiben unangetastet.

---

## 5. Datenmodell

### 5.1 Domänenmodell (Value Types, `MarqetCore`)

```swift
struct ShoppingItem: Identifiable, Hashable, Sendable {
    let id: String              // EKReminder.calendarItemIdentifier
    var title: String
    var userNotes: String?      // Notizen ohne Marker
    var storeRef: StoreRef?     // nil = unsortiert
    var isCompleted: Bool
    var completionDate: Date?
    var creationDate: Date?
}

enum StoreRef: Hashable, Sendable {
    case known(Store.ID)
    case unresolved(name: String)   // wird beim Laden in .known aufgelöst (auto-create)
}

struct Store: Identifiable, Hashable, Sendable {
    let id: UUID
    var catalogKey: String?     // z. B. "aldi-sued"; nil bei eigenen Läden
    var name: String            // kanonischer Name, wird in den Marker geschrieben
    var aliases: [String]
    var colorHex: String
    var symbol: StoreSymbol     // Monogramm oder SF Symbol
    var sortIndex: Int
    var origin: Origin          // .catalog, .custom, .detected
    var type: StoreType         // .supermarket, .drugstore, .hardware … (steuert Kategorien & KI)
    var plannedAt: Date?        // vom Nutzer als (leere) Card hinzugefügt → bleibt sichtbar
}

enum ItemCategory: String, CaseIterable, Sendable {
    case produce, bakery, dairyEggs, cheese, meat, fish, frozen, pantry, baking,
         breakfast, snacks, beverages, alcohol, personalCare, household, baby, pet, other
}
```

### 5.2 Lokale Persistenz (SwiftData, CloudKit-Private-DB-Sync)

Die Daten syncen zwischen den eigenen Geräten und überstehen eine Neuinstallation. Wegen CloudKit: alle Attribute optional bzw. mit Default, **keine `.unique`-Constraints**, Dubletten werden in Code bereinigt.

| Entity | Felder | Zweck |
|---|---|---|
| `StoreEntity` | id, catalogKey, name, aliases, colorHex, symbol, sortIndex, origin, type, plannedAt, createdAt | Laden-Konfiguration + Lebenszyklus |
| `AssignmentMemory` | itemKey, storeID, count, lastAssignedAt | „Milch → Aldi (5×)“ |
| `CategoryMemory` | itemKey, category, isUserCorrection | Gelernte bzw. korrigierte Kategorie pro Item |
| `CategoryOrder` | storeID, category, position (0…1), samples, isManual | Laufweg auf Kategorie-Ebene (Pro) bzw. manuelle Reihenfolge (Free) |
| `ItemOrder` | storeID, itemKey, position (0…1), samples, isManual | Feinsortierung *innerhalb* einer Kategorie |
| `StoreLocation` *(Modell in v1.0, UI ab v1.2)* | id, storeID, mapItemIdentifier, name, latitude, longitude, address, isPreferred | Filialen |

Nur in `UserDefaults` (gerätespezifisch):

| Key | Inhalt |
|---|---|
| `selectedCalendarID` | `EKCalendar.calendarIdentifier` (ist pro Gerät verschieden, deshalb nicht synced) |
| `triageMode` | `.single` / `.board` |
| `seenUnassignedIDs` | Set von Item-IDs, zu denen schon gefragt wurde |
| `lastShoppingActivity` | Zeitpunkt des letzten Abhakens (für das Ende der Einkaufssitzung, 7.2) |
| `proEntitlementCache` | Offline-Cache des Kaufstatus |

### 5.3 Item-Key-Normalisierung

Das Gelernte hängt am **normalisierten Titel**, nicht an der Reminder-ID. IDs können sich bei iCloud-Resyncs ändern, und „Milch“ nächste Woche ist ein neuer Reminder.

```
"2x Bio-Milch 1,5%  " → "bio-milch 1,5%"   (Menge entfernt)
"Milch!"              → "milch"
"500 g Hackfleisch"   → "hackfleisch"
```

Regeln: lowercase · trim · führende Mengenangaben entfernen (`^\d+([.,]\d+)?\s*(x|×|stk\.?|st\.?|g|kg|l|ml|pck\.?|packung(en)?|dose(n)?|flasche(n)?)?\s+`) · trailing Satzzeichen entfernen · Mehrfach-Whitespace zusammenfassen. Für das Matching zusätzlich diakritik-gefaltet.

---

## 6. Intelligenz

### 6.1 Vorschlags-Pipeline

Für jedes unsortierte Item wird der Reihe nach geprüft (der erste Treffer gewinnt):

| Stufe | Quelle | Free | Pro |
|---|---|---|---|
| 1 | **Gedächtnis exakt:** `AssignmentMemory[itemKey]` | Vorschlag hervorgehoben | Auto-Zuordnung bei hoher Sicherheit |
| 2 | **Gedächtnis unscharf:** Token-Match („bio-milch“ enthält „milch“) | Vorschlag hervorgehoben | Nur Vorschlag |
| 3 | **Apple Intelligence** (Foundation Models, on-device) | – | Vorschlag ✨ |
| 4 | **Keyword-Heuristik** nach Ladentyp (Fallback ohne Apple Intelligence) | – | Vorschlag ✨ |

**Sicherheit („hoch“)**: Top-Laden hat `count ≥ 2` **und** ≥ 80 % Anteil aller Zuordnungen dieses Keys. Nur „hoch“ führt zur Auto-Zuordnung. KI-Vorschläge ordnen **nie** automatisch zu.

**Lernen**: Jede bestätigte Zuordnung (manuell, Vorschlag angenommen, Auto-Zuordnung nicht rückgängig gemacht) erhöht `count`. Eine rückgängig gemachte Auto-Zuordnung senkt ihn.

### 6.2 Apple Intelligence (Foundation Models)

- Verfügbarkeit: `SystemLanguageModel.default.availability`. Ist das Modell nicht verfügbar, greift Stufe 4 ohne Fehlermeldung.
- **Batch-Request** für alle unbekannten Items gleichzeitig (Latenz).
- Die Ladennamen sind erst zur Laufzeit bekannt, deshalb **`DynamicGenerationSchema`** mit Enum der aktiven Läden plus `"unbekannt"`. So kann das Modell keine Läden erfinden.
- Der Prompt enthält pro Laden den Ladentyp aus dem Katalog (Discounter, Drogerie, Baumarkt …), damit „Zahnpasta → dm“ funktioniert, auch wenn dm neu ist.
- Ergebnisse werden pro `itemKey` für die Sitzung gecacht.

### 6.3 Kategorien (v1.0)

Apple kategorisiert in Erinnerungen hervorragend, aber **Abschnitte und Kategorien sind über EventKit nicht lesbar** (Stand: SDK iOS/macOS 27). Deshalb baut Marqet eine eigene Kategorisierung, die mindestens genauso gut sein soll.

**Kategorien** (angelehnt an Apple, damit sie vertraut wirken): Obst & Gemüse · Brot & Backwaren · Milchprodukte & Eier · Käse · Fleisch & Wurst · Fisch · Tiefkühl · Vorrat (Nudeln, Reis, Konserven) · Backzutaten · Frühstück & Aufstriche · Snacks & Süßes · Getränke · Wein, Bier & Spirituosen · Drogerie & Pflege · Haushalt · Baby · Tier · Sonstiges.

**Pipeline** (der erste Treffer gewinnt):

| Stufe | Quelle | Free | Pro |
|---|---|---|---|
| 1 | **Gelernt:** `CategoryMemory[itemKey]`, die Korrektur des Nutzers hat Vorrang | ✓ | ✓ |
| 2 | **Wörterbuch** (mitgeliefert, ca. 2.500 Begriffe DE/EN inkl. AT/CH-Varianten wie Paradeiser, Rüebli). **Kompositum-Regel:** Der längste bekannte Wortteil am Ende gewinnt („Vollkorn**brot**“ → Backwaren, „Tomaten**mark**“ → Ausnahme-Eintrag Vorrat) | ✓ | ✓ |
| 3 | **Foundation Models** mit `@Generable` und Enum der Kategorien, im Batch | – | ✓ |
| 4 | Sonstiges | ✓ | ✓ |

- **Korrigieren:** Long Press → „Kategorie ändern“, oder das Item in der Card in einen anderen Abschnitt ziehen. Wird als `CategoryMemory(isUserCorrection: true)` gespeichert, genau wie bei Apple.
- Die Kategorie wird **nicht** in die Notizen geschrieben (Notizen bleiben sauber). In geteilten Listen kategorisiert jedes Gerät selbst.
- **Nur für Lebensmittel-Läden:** Kategorie-Abschnitte werden für `supermarket`, `discounter`, `organic` und `market` angezeigt. Drogerie, Baumarkt, Möbel und Online zeigen eine flache Liste (gegebenenfalls später eigene Kategorien-Sets).
- Das Wörterbuch ist eine eigene Datenbasis (mit KI-Unterstützung erzeugt und manuell kuratiert). **Kein Import aus Open Food Facts** wegen der Share-Alike-Pflichten der ODbL-Lizenz.

### 6.4 Laufweg-Sortierung (Pro): auf Kategorie-Ebene

Gelernt wird die Reihenfolge der **Kategorien pro Laden**, zusätzlich die Feinreihenfolge der Items innerhalb einer Kategorie. Das ist robuster als rein auf Item-Ebene: Schon nach 1–2 Einkäufen sitzen auch nie gesehene Items am richtigen Platz („Zucchini“ landet bei Obst & Gemüse und damit dort, wo dieser Abschnitt in *deinem* Aldi liegt).

- **Einkaufssitzung** = Abhak-Vorgänge auf derselben Laden-Card mit Abständen < 20 min. Gewertet wird sie nur ab **≥ 3 Abhakungen**. Das filtert „zu Hause abhaken“ weitgehend heraus.
- **Kategorie-Position** in einer Sitzung: der Durchschnittsrang ihrer Items, normiert auf [0, 1]. **Item-Position** innerhalb der Kategorie wird genauso berechnet.
- Update: gleitender Mittelwert `pos = pos·(1−α) + neu·α`, mit `α = 1/(samples+1)` bis 3 Samples, danach `α = 0,3`.
- **Startwert** ohne Daten: die typische Supermarkt-Reihenfolge (Obst & Gemüse → Brot → … → Tiefkühl → Getränke → Drogerie).
- **Anzeige:** Abschnitte nach Kategorie-Position. Innerhalb eines Abschnitts stehen unbekannte Items oben, danach bekannte nach Item-Position.
- Manuelles Verschieben (Abschnitt oder Item) setzt `isManual = true`. Lernen verändert manuelle Positionen nur halb so schnell.
- **Free:** Standard-Reihenfolge, Abschnitte in den Laden-Einstellungen per Drag umsortierbar, Items innerhalb alphabetisch.

---

## 7. UX & Screens

### 7.1 App-Struktur

```
RootView
├── OnboardingFlow            (erster Start / keine Liste / keine Berechtigung)
└── ShoppingScreen            (Hauptscreen)
    ├── StorePager            (horizontale Cards: Unsortiert · Läden · Weitere Läden)
    ├── QuickAdd              (Plus-Button → Inline-Eingabe + Laden-Chipleiste)
    ├── AddStoreSheet         (Katalog | Eigener Laden | v1.2: Karte)
    ├── TriagePrompt (Sheet)  → TriageScreen (Einzeln | Board)
    ├── Settings (Sheet)
    └── Paywall (Sheet)
```

### 7.2 Hauptscreen

```
┌─────────────────────────────────┐
│ Einkaufen                   ⚙︎   │  ← Listenname, Einstellungen (Glass-Toolbar)
│ ┌┐┌─────────────────────────┐┌┐ │
│ ││││ ▓▓▓ ALDI SÜD      5 offen││ │  ← Header in Laden-Farbe
│ ││││ OBST & GEMÜSE           ││ │  ← Kategorie-Abschnitt (Laufweg-Reihenfolge)
│ ││││ ○ Bananen               ││ │
│ ││││ BROT & BACKWAREN        ││ │
│ ││││ ○ Brot                  ││ │
│ ││││ MILCHPRODUKTE & EIER    ││ │
│ ││││ ○ Milch                 ││ │
│ ││││   laktosefrei           ││ │  ← Nutzernotiz (ohne Marker)
│ ││││ ○ Eier                  ││ │
│ ││││ ○ Butter                ││ │
│ ││││   Erledigte anzeigen    ││ │
│ └┘└─────────────────────────┘└┘ │  ← Nachbar-Cards lugen ~16 pt hervor
│        ◦  ●  ◦  ◦            (+)│  ← Punkte in Laden-Farben · Glass-FAB
└─────────────────────────────────┘
```

- **Pager:** `ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetBehavior(.viewAligned)` + `.containerRelativeFrame`. Die Card nimmt die gesamte Höhe zwischen Toolbar und Indikator ein. Innen scrollt die Liste vertikal.
- **Reihenfolge:** `Unsortiert` (nur wenn > 0) → sichtbare Läden in Nutzer-Reihenfolge → **`Weitere Läden`** (immer als letzte Card, siehe 7.8).
- **Seitenindikator:** Punkte in Laden-Farbe, antippbar und per Scrub springbar, die letzte Card als `+`. VoiceOver-Label „Aldi Süd, 5 offen, Seite 2 von 4“.
- **Leerer Zustand** (gar nichts offen): Es bleibt nur die Card „Weitere Läden“, mit Kopfzeile „Alles eingekauft 🎉“. Sie ist zugleich der Einstieg in die nächste Planung.
- **Pull-to-Refresh** auf jeder Card.

**Laden-Lebenszyklus: wann ist eine Laden-Card sichtbar?**

| Zustand | Wie entsteht er | Sichtbar | Endet durch |
|---|---|---|---|
| **Aktiv** | ≥ 1 offenes Item | ✓ | Letztes Item erledigt, gelöscht oder verschoben |
| **Geplant** | Der Nutzer fügt den Laden bewusst hinzu (Card „Weitere Läden“, neuer Laden, Chipleiste). `plannedAt` wird gesetzt | ✓ Empty State „Noch leer – tippe + um etwas für Lidl hinzuzufügen“ | Nur durch: **Einkauf abgeschlossen** (Laden war aktiv und ist durch Abhaken leer geworden, Sitzung beendet) **oder** manuell „Aus Übersicht entfernen“. **Kein Zeitablauf.** |
| **Leer eingekauft** | Aktiv/geplant → durch **Abhaken** leer geworden | ✓ „Alles erledigt bei Aldi ✓“ + Button „Ausblenden“ | **Ende der Einkaufssitzung:** App war > 30 min im Hintergrund bzw. ohne Abhak-Aktivität, oder Tipp auf „Ausblenden“. Dann wird `plannedAt = nil` gesetzt → ausgeblendet |
| **Leer geräumt** | Aktiv → durch **Löschen oder Verschieben** leer geworden | ✓ bis man weg wischt | Wegwischen. War der Laden geplant, bleibt er „Geplant“ |
| **Ausgeblendet** | Kein offenes Item, nicht geplant | – (liegt in „Weitere Läden“) | Item kommt hinzu oder der Nutzer fügt ihn hinzu |

Leitgedanken:
- **Was der Nutzer bewusst hinzufügt, bleibt, bis er es wegnimmt oder dort eingekauft hat.** Damit funktioniert Planen („erst alle Läden für den Wocheneinkauf anlegen, dann befüllen“) ohne die Angst, dass Cards verschwinden.
- **Die Cards springen nie unter dem Finger weg.** Die gerade sichtbare Card wird nie entfernt, eine Änderung wirkt erst nach dem Wegwischen bzw. beim nächsten Öffnen.
- `plannedAt` synct über SwiftData/CloudKit auf die eigenen Geräte. Personen in einer geteilten Liste sehen geplante leere Läden nicht, weil in Erinnerungen dafür kein Item existiert. Das ist bewusst so.

**Item-Interaktionen**

| Geste | Aktion |
|---|---|
| Tipp auf Kreis | Abhaken: Kreis füllt sich in Laden-Farbe, Haptik, **sofort** nach EventKit schreiben, Zeile verschwindet nach 1,5 s. Erneuter Tipp innerhalb dieser Zeit = Undo |
| Tipp auf Titel | Inline umbenennen |
| Swipe von links | „Laden ändern“ (Menü mit Läden) |
| Swipe von rechts | Löschen, mit Undo-Toast (Undo legt den Reminder mit gleichen Feldern neu an) |
| Long Press | Kontextmenü: Laden ändern ▸, Kategorie ändern ▸, Umbenennen, Notiz bearbeiten, Löschen |
| Drag innerhalb Card | Reihenfolge ändern bzw. in einen anderen Kategorie-Abschnitt ziehen (= Kategorie-Korrektur) |

**Card-Menü** (`…` im Card-Header): Abschnitte sortieren · Aus Übersicht entfernen (nur wenn leer) · Laden bearbeiten · *(v1.1)* Aktuelles Prospekt

**Erledigte anzeigen** (Footer der Card): zeigt die Items dieses Ladens, die in den letzten 7 Tagen erledigt wurden. Ein Tipp macht das Abhaken rückgängig („nochmal kaufen“). Geladen wird erst bei Bedarf über `predicateForCompletedReminders`.

### 7.3 Quick Add (Plus-Button)

- *Rev. 3:* **System-Toolbar-Item** (`.bottomBar`, rechts) statt eigenem FAB. Auf dem iPhone sieht es aus wie ein Glass-Button unten rechts, auf dem iPhone Duo wandert es automatisch in die senkrechte Leiste am Daumen ([KONZEPT-DUO-IPAD.md §3](KONZEPT-DUO-IPAD.md)).
- Tippen öffnet eine **Inline-Eingabezeile am Ende der aktiven Card** mit fokussierter Tastatur.
- Return legt das Item an, und direkt darunter öffnet sich eine neue leere Zeile (Serien-Eingabe wie in Reminders). Wegtippen bzw. Tastatur schließen beendet die Eingabe.
- **Zuordnung:** Laden-Card → Marker dieses Ladens. Unsortiert-Card → ohne Marker. Auf der Card „Weitere Läden“ öffnet sich die Eingabe mit Ziel „Unsortiert“ und der Chipleiste (siehe unten).
- Angelegt wird in der gewählten Liste. Der Titel ist Freitext, Mengen bleiben im Titel („2x Milch“). Die Kategorie wird sofort bestimmt, und das Item erscheint im richtigen Abschnitt.

**Laden-Chipleiste über der Tastatur** (*umgesetzt in M2:* als Teil einer festen Eingabeleiste über der Tastatur statt als Zeile in der Card, siehe unten):

```
┌─────────────────────────────────────────┐
│ [Unsortiert] [● Aldi] [Lidl] [dm] [+ …] │  ← horizontal scrollbar, alle eigenen Läden
├─────────────────────────────────────────┤
│  q  w  e  r  t  z  u  i  o  p  ü        │
```

- Der aktive Chip ist das Ziel für die nächsten Items (Start: der Laden der aktuellen Card).
- Tippt man einen anderen Laden an, wechselt der Pager zu dessen Card, die Eingabezeile wandert mit und die Tastatur bleibt offen. Ist der Laden ausgeblendet, wird er dabei als **Geplant** eingeblendet. Man sieht also immer, wo das Item landet.
- `+ …` öffnet „Laden hinzufügen“ (siehe 7.8) und kehrt danach in die Eingabe zurück.

*Umsetzung M2:* Die Eingabe ist **ein** Textfeld in einer Glass-Leiste über der Tastatur (Chips oben, Feld unten), nicht eine Inline-Zeile pro Card. Beim Laden-Wechsel bleibt so dasselbe Feld fokussiert, und die Tastatur springt nie. Das neue Item erscheint sofort unten in der Ziel-Card, die dorthin scrollt. Return legt das Item an und hält die Tastatur offen (UIKit-Feld mit `textFieldShouldReturn → false`). Eine eingefügte Liste mit mehreren Zeilen wird in einzelne Items zerlegt.

**Long Press auf den Plus-Button:** Menü „Hinzufügen zu …“ mit allen Läden (zuletzt benutzte oben) und „Unsortiert“. Die Auswahl springt zur Card und öffnet die Eingabe.

**Items zu einem Laden ohne Card hinzufügen:** Dafür gibt es drei gleichwertige Wege. Keiner zwingt über Umwege:
1. Card „Weitere Läden“ → Laden antippen → er wird als geplante Card eingeblendet und die Eingabe öffnet sich.
2. Long Press auf den Plus-Button → Laden wählen.
3. In der laufenden Eingabe auf der Chipleiste den Laden wechseln.

### 7.4 Zuordnen-Flow

**Trigger-Logik** (bei jedem Wechsel auf `scenePhase == .active` und nach `EKEventStoreChanged`):

```
reload()
if isPro && autoAssignEnabled:
    für jedes unsortierte Item mit Sicherheit "hoch": Marker schreiben
    wenn ≥1 → Toast "5 Items automatisch zugeordnet · Rückgängig"
U   = unsortierte Items
neu = U − seenUnassignedIDs
if neu nicht leer && kein Sheet offen && Nutzer tippt gerade nicht:
    TriagePrompt zeigen
seenUnassignedIDs ∪= U
```

- **Erster Start nach dem Onboarding:** Bestehende Items ohne Marker → direkt in den Zuordnen-Screen.
- **TriagePrompt:** kompaktes Sheet (Detent ~220 pt): „3 neue Items“ + Chips mit Titeln + **[Zuordnen]** **[Später]**. „Später“ fragt erst wieder, wenn *neue* Items dazukommen. Die Unsortiert-Card bleibt als Einstieg.
- **TriageScreen:** Vollbild-Sheet, oben ein Segmented Control **Einzeln | Board** (Auswahl wird gemerkt), Button „Alle Vorschläge übernehmen (5)“, wenn Vorschläge existieren.

**Modus Einzeln**

```
┌─────────────────────────────────┐
│ Abbrechen    Einzeln|Board   Fertig │
│            3 von 7              │
│      ┌───────────────────┐      │
│      │      Milch        │      │
│      │   laktosefrei     │      │
│      └───────────────────┘      │
│  ┌─────────────┐┌────────────┐  │
│  │ ↺ Aldi Süd  ││   Rewe     │  │  ← Vorschlag hervorgehoben (↺ gelernt / ✨ KI)
│  └─────────────┘└────────────┘  │
│  ┌─────────────┐┌────────────┐  │
│  │    dm       ││   Markt    │  │
│  └─────────────┘└────────────┘  │
│  ↶ Rückgängig   Überspringen   + Laden │
└─────────────────────────────────┘
```

- Die Laden-Buttons stehen in **fester** Reihenfolge (Muskelgedächtnis), der Vorschlag wird nur hervorgehoben.
- Tippen: Item fliegt zum Button, Haptik, nächstes Item. Rückgängig nimmt die letzte Zuordnung zurück.
- Ende: Zusammenfassung „7 Items zugeordnet“. **Free:** dezente Upsell-Zeile „Mit Pro wären 5 davon automatisch zugeordnet worden“ (lokal berechnet).

**Modus Board**

```
┌─────────────────────────────────┐
│ ┌────────┐┌────────┐┌────────┐  │
│ │Aldi (5)││Rewe (2)││ dm (1) │  │  ← Drop-Zonen, vergrößern sich beim Drüberziehen
│ └────────┘└────────┘└────────┘  │
│ ┌────────┐┌────────┐            │
│ │Markt   ││ + Neu  │            │
│ └────────┘└────────┘            │
│ ─────────────────────────────── │
│ ≡ Milch            ↺ Aldi       │  ← Vorschlags-Badge
│ ≡ Zahnpasta        ✨ dm        │
│ ≡ Tomaten                       │
│ ≡ Batterien                     │
└─────────────────────────────────┘
```

- Items sind `draggable`, Läden sind `dropDestination`. **Mehrfachauswahl** und gemeinsames Ziehen über die Drag-APIs von iOS 26 (im Spike verifizieren).
- **Tap-Fallback:** Items antippen (Auswahl), dann Laden antippen. Das ist auch die Barrierefreiheits-Variante.
- VoiceOver: Accessibility-Aktionen pro Item „Zu Aldi Süd zuordnen“ usw.

### 7.5 Onboarding

1. **Willkommen:** drei Nutzenversprechen (Siri rein → nach Läden sortiert → Laufweg).
2. **Berechtigung:** erst erklären, dann System-Dialog. Abgelehnt → Erklärung + Button „Einstellungen öffnen“.
3. **Liste wählen:** alle Erinnerungslisten mit Anzahl offener Items. Vorauswahl per Namensheuristik („Einkauf“, „Einkaufsliste“, „Einkaufen“, „Lebensmittel“, „Shopping“, „Groceries“). Alternativ „Neue Liste ‚Einkaufen‘ anlegen“ (in der Quelle von `defaultCalendarForNewReminders()`).
4. **Läden wählen:** Katalog nach Region (DE/AT/CH aus `Locale.current.region`, umschaltbar), Suche, Mehrfachauswahl. Die Reihenfolge der Auswahl ergibt die Card-Reihenfolge. Dazu „Eigenen Laden anlegen“. Mindestens 1 Laden.
5. **Siri-Tipp:** „Sag: ‚Hey Siri, setz Milch auf meine Einkaufsliste‘ – Marqet sortiert es danach ein.“
6. Bestehende Items → Zuordnen-Screen.

### 7.6 Einstellungen

- **Liste:** wechseln
- **Läden:** Reihenfolge (Drag), hinzufügen (Katalog/eigener), bearbeiten (Name, Typ, Farbe, Symbol, **Reihenfolge der Kategorie-Abschnitte**), löschen (siehe 4.4)
- **Laden-Reihenfolge im Pager:** v1.0 nur „Manuell“. v1.2 zusätzlich „Entfernung“ und „Smart“ (siehe 14.2)
- **Intelligenz** (Pro, mit Schloss für Free): Auto-Zuordnung · KI-Vorschläge · Laufweg-Sortierung · „Gelerntes zurücksetzen“
- **Zuordnen:** Standardmodus Einzeln/Board
- **Marqet Pro:** kaufen · Käufe wiederherstellen
- **Über:** Datenschutz, Marken-Hinweis, Feedback (Mail), Version

### 7.7 Design

- **Liquid Glass** für Toolbar, FAB, Sheets und Segmented Control. Die Cards selbst sind **opak** (Lesbarkeit im Laden, auch bei Sonne).
- Card-Header: kräftige Laden-Farbe mit leichtem Verlauf, Monogramm bzw. SF Symbol, Name, Anzahl offener Items.
- Laden-Farben: kuratierte Palette, jede Farbe für Weiß- und Dunkeltext geprüft (WCAG AA). Katalog-Ketten haben **markenähnliche, nicht identische** Farben.
- Dark Mode vollständig, Dynamic Type bis AX5 (Cards scrollen), Reduce Motion ersetzt Flug-Animationen durch Überblendungen.
- Haptik: Abhaken (light), Zuordnen (medium), Drop (success).

### 7.8 Card „Weitere Läden“ & Laden anlegen

Die letzte Card im Pager, immer vorhanden:

```
┌─────────────────────────────┐
│ Weitere Läden               │
│                             │
│ Deine Läden                 │
│ ┌───────┐┌───────┐┌───────┐ │
│ │ Lidl  ││  dm   ││ Markt │ │  ← ausgeblendete eigene Läden (Laden-Farbe)
│ └───────┘└───────┘└───────┘ │
│ ┌───────┐                   │
│ │ Obi   │                   │
│ └───────┘                   │
│                             │
│ Vorschläge                  │
│ ┌───────┐┌───────┐          │
│ │ Rewe  ││Rossm. │          │  ← Katalog-Ketten der Region, noch nicht angelegt
│ └───────┘└───────┘          │
│                             │
│ [ + Laden hinzufügen ]      │
│ [ ☐ Mehrere planen ]        │
└─────────────────────────────┘
```

- **Tipp auf eigenen Laden:** Er wird als **Geplant** eingeblendet (vor „Weitere Läden“, an seiner Position in der Nutzer-Reihenfolge), der Pager springt hin und die Eingabe öffnet sich.
- **Tipp auf Vorschlag:** Der Laden wird aus dem Katalog angelegt und dann wie oben behandelt. **Free/Pro:** Es gibt kein Laden-Limit (Entscheidung #15).
- **„Mehrere planen“:** Mehrfachauswahl-Modus. Man wählt z. B. Aldi, dm und Markt, dann „3 Läden hinzufügen“. Alle werden als Geplant eingeblendet, der Pager springt zum ersten. Das deckt den Planungs-Workflow ab: erst Läden, dann Items.
- **Vorschläge:** v1.0 zeigt Katalog-Ketten der Region, sortiert nach Popularität (Reihenfolge im Katalog). v1.2 zeigt Ketten mit einer Filiale in der Nähe.

**„Laden hinzufügen“** (Sheet, auch aus Einstellungen, Chipleiste und Zuordnen-Screen erreichbar):

| Tab | v1.0 | v1.2 |
|---|---|---|
| **Katalog** | Suche + Liste der Ketten der Region (DE/AT/CH umschaltbar), mit Farbe und Monogramm | + Entfernung zur nächsten Filiale |
| **Eigener Laden** | Name, Ladentyp (steuert Kategorien und KI), Farbe aus der Palette, SF Symbol aus einer kuratierten Auswahl | – |
| **Karte** | – | POI-Suche (siehe 14.1): Filiale wählen, die Kette wird automatisch erkannt oder ein eigener Laden angelegt |

Nach dem Anlegen: Der Laden ist **Geplant**, und bei Aufruf aus dem Pager springt dieser zur neuen Card.

---

## 8. Laden-Katalog

Mitgeliefertes, versioniertes `StoreCatalog.json` (Update mit App-Releases):

```json
{
  "version": 1,
  "stores": [
    {
      "key": "aldi-sued",
      "name": "Aldi Süd",
      "aliases": ["Aldi", "ALDI SÜD", "Aldi Sued"],
      "regions": ["DE"],
      "type": "discounter",
      "color": "#1C3F94",
      "monogram": "AS",
      "leafletURL": "https://…",          // v1.1: offizielle Prospektseite
      "mapSearchTerms": ["Aldi Süd", "ALDI"] // v1.2: POI-Erkennung
    }
  ]
}
```

**Umfang v1** (≈ 40 Einträge):
- **DE:** Aldi Nord, Aldi Süd, Lidl, Rewe, Edeka, Kaufland, Netto, Penny, Norma, Globus, Real/Marktkauf, dm, Rossmann, Müller, Alnatura, denn's, Bio Company, Hornbach, Obi, Bauhaus, Ikea, Getränke Hoffmann
- **AT:** Billa, Billa Plus, Spar, Eurospar, Interspar, Hofer, Lidl, Penny, dm, Bipa, MPreis
- **CH:** Migros, Coop, Denner, Aldi Suisse, Lidl, Volg, Manor
- **Generisch (alle Regionen):** Markt, Bäcker, Metzger, Apotheke, Getränkemarkt, Baumarkt, Drogerie, Bioladen, Online

`type` ∈ `discounter, supermarket, drugstore, organic, hardware, furniture, beverage, bakery, butcher, pharmacy, market, online, other`. Die Typen steuern KI-Prompt und Keyword-Heuristik.

**Recht:** keine Logos und keine Wortmarken-Grafiken, nur Namen (beschreibende Nutzung). Unter „Über“ steht: „Marqet steht in keiner Verbindung zu den genannten Handelsketten. Alle Marken gehören ihren jeweiligen Inhabern.“

---

## 9. Architektur

### 9.1 Stack

- Swift 6 (Strict Concurrency), SwiftUI, `@Observable`, iOS 26.0 Deployment Target, Xcode 27
- EventKit · SwiftData (+ CloudKit) · FoundationModels · StoreKit 2
- Swift Testing, XCUITest
- Keine Third-Party-Dependencies

### 9.2 Projektstruktur

```
marqet/
├── Marqet.xcodeproj
├── Marqet/                              App-Target
│   ├── App/            MarqetApp, AppModel, RootView, Environment
│   ├── Features/
│   │   ├── Shopping/   ShoppingScreen, StorePager, StoreCard, ItemRow,
│   │   │               QuickAddRow, PageIndicator, CompletedSection
│   │   ├── Triage/     TriagePrompt, TriageScreen, SingleTriageView, BoardTriageView
│   │   ├── Onboarding/
│   │   ├── Settings/
│   │   └── Paywall/
│   ├── DesignSystem/   Farben, Card-Styles, Haptics, StoreBadge
│   └── Resources/      Localizable.xcstrings, Assets
├── Packages/MarqetKit/                  lokales SPM-Package
│   ├── Sources/
│   │   ├── MarqetCore/         Modelle, StoreMarker (Parser/Writer), ItemKeyNormalizer,
│   │   │                       SuggestionEngine, CategoryClassifier (+ Wörterbuch),
│   │   │                       RouteSorter, StoreVisibilityPolicy, CardBuilder,
│   │   │                       TriagePolicy, StoreCatalog (+ StoreCatalog.json als Ressource)
│   │   │                       → nur Foundation, 100 % unit-testbar
│   │   ├── MarqetReminders/    ReminderGateway (Protocol), EventKitGateway (actor)
│   │   ├── MarqetPersistence/  SwiftData-Modelle, MemoryRepository
│   │   ├── MarqetIntelligence/ FoundationModelsClassifier, KeywordClassifier
│   │   └── MarqetPurchases/    ProEntitlement (StoreKit 2)
│   └── Tests/                  je Modul, Swift Testing
└── docs/KONZEPT.md
```

### 9.3 Datenfluss

```
          ┌──────────────┐  EKEventStoreChanged / scenePhase
          │  EventKit    │──────────────────┐
          └──────▲───────┘                  ▼
     save/remove │           ┌──────────────────────────┐
                 │           │ EventKitGateway (actor)  │  EKReminder → ReminderSnapshot (Sendable)
                 └───────────│  fetch / create / update │
                             └────────────┬─────────────┘
                                          ▼
┌────────────────┐   ┌────────────────────────────────────┐   ┌───────────────────┐
│ SwiftData      │◀─▶│ AppModel (@MainActor, @Observable) │◀─▶│ SuggestionEngine  │
│ Stores, Memory │   │ items, stores, cards, triageState  │   │ + Classifier (AI) │
└────────────────┘   └───────────────┬────────────────────┘   └───────────────────┘
                                     ▼
                          SwiftUI Views (read-only + Intents)
```

- `EKEventStore` ist **eine** Instanz im Actor `EventKitGateway`. `EKReminder` verlässt den Actor nie. Schreibzugriffe erfolgen per ID (`calendarItem(withIdentifier:)`), **seriell** (Abhak-Salven gehen nicht verloren).
- `fetchReminders(matching:)` wird mit `withCheckedContinuation` gewrappt. Refresh-Notifications werden per Debounce (300 ms) gebündelt.
- **Optimistic UI:** `AppModel` ändert den Zustand sofort. Schlägt der Write fehl → Rollback + Toast.
- `CardBuilder` (pur, getestet): items + stores + Order-Daten + „gepinnte“ Card → `[Card]`.
- `ReminderGateway`-Protocol mit In-Memory-Mock für Tests und SwiftUI-Previews.

### 9.4 Kauf (StoreKit 2)

- Non-Consumable `…marqet.pro`, **Familienfreigabe aktiviert** (passt zum Haushalts-Szenario). Preisvorschlag 6,99 €.
- `Transaction.currentEntitlements` beim Start, Listener auf `Transaction.updates`, Offline-Cache in UserDefaults.
- Paywall als eigene View mit `ProductView`: Auslöser sind gesperrte Pro-Schalter, ✨-Hinweise und der Upsell am Ende des Zuordnens. **Kein** Modal beim App-Start.
- StoreKit-Konfigurationsdatei für lokale Tests.

### 9.5 Datenschutz & Compliance

- Kein Backend, keine Analytics, kein Tracking. App-Privacy-Label: **„Keine Daten erfasst“**.
- Trotzdem nötig: **Datenschutzerklärung-URL** (App-Store-Pflicht) und Support-URL. Für den kommerziellen Vertrieb in DE ein Impressum auf der Support-Seite.
- Crash- und Performance-Daten über Xcode Organizer bzw. MetricKit (Apple-seitig, opt-in des Nutzers).
- App-Review-Notiz: Die App benötigt Erinnerungen-Zugriff. Demo-Schritte beilegen.

---

## 10. Edge Cases

| Fall | Verhalten |
|---|---|
| Mehrere Marker in einer Notiz | Letzter gilt. Beim nächsten Write werden alle bereinigt |
| Marker mit unbekanntem Laden | Eigener Laden wird automatisch angelegt (`detected`) |
| Marker manuell in Reminders geändert | Wird beim nächsten Refresh übernommen, das Lernen wird **nicht** beeinflusst |
| Nutzer bearbeitet parallel die Notiz | `refresh()` vor dem Write, Freitext bleibt erhalten |
| Gewählte Liste gelöscht / nicht mehr gefunden | Screen „Liste nicht gefunden“ → Liste neu wählen |
| Berechtigung zur Laufzeit entzogen | Beim nächsten Aktivwerden Status prüfen → Berechtigungs-Screen |
| Item in andere Liste verschoben | Verschwindet aus Marqet |
| Einkaufslisten-Typ (Reminders-Abschnitte) | Funktioniert, die Abschnitte in Reminders bleiben unberührt (Spike prüft das) |
| Liste ohne iCloud („Auf meinem iPhone“) | Funktioniert, nur ohne Geräte-Sync |
| Aktive Card wird leer | Bleibt bis zum Wegwischen stehen (siehe 7.2) |
| 300+ offene Items | `LazyVStack`, Snapshots diffen; Ziel < 100 ms Refresh |
| Gleiches Item zweimal („Milch“ ×2) | Zwei Zeilen, keine Deduplizierung |
| Laden gelöscht, erledigte Items tragen noch den Marker | Unberührt, fließen nicht in Cards ein |
| Free-Nutzer mit bestehendem Pro-Lernen (Kauf erstattet) | Lernen bleibt gespeichert, nur Auto/KI/Laufweg aus |
| Geplanter Laden, Partner fügt über Erinnerungen ein Item mit Marker hinzu | Laden wird aktiv, `plannedAt` bleibt, bis dort eingekauft wurde |
| Geplanter Laden auf Gerät A, Nutzer öffnet Gerät B | Über CloudKit ebenfalls geplant (eigene Geräte) |
| Alle Läden leer, nichts geplant | Nur die Card „Weitere Läden“ mit „Alles eingekauft 🎉“ |
| Item in Drogerie-Laden („Zahnpasta“ bei dm) | Flache Liste ohne Kategorie-Abschnitte |
| Item wird zu einem Laden verschoben, der gerade als „Leer eingekauft“ angezeigt wird | Wird wieder aktiv, die Anzeige „Alles erledigt“ verschwindet |

---

## 11. Qualitätssicherung

**Unit-Tests (MarqetCore, Pflicht vor jeder UI)**
- `StoreMarker`: ≥ 30 tabellarische Fälle (leer, nur Marker, Freitext + Marker, mehrere Marker, Marker mitten im Text, Variation Selector, CRLF, Whitespace, Emoji im Freitext, byte-genauer Erhalt).
- `ItemKeyNormalizer`: Mengen, Einheiten, Umlaute, Satzzeichen.
- `SuggestionEngine`: Schwellwerte, Undo-Lernen, unscharfer Match.
- `CategoryClassifier`: Wörterbuch-Treffer, Komposita und Ausnahmen, Korrektur hat Vorrang, AT/CH-Begriffe. **Goldset mit 500 realen Einkaufsitems, Ziel ≥ 90 % korrekt ohne KI.**
- `RouteSorter`: Sitzungserkennung, EMA auf Kategorie- und Item-Ebene, unbekannte oben, manuelle Overrides.
- `StoreVisibilityPolicy`: alle Übergänge der Lebenszyklus-Tabelle (7.2), Sitzungsende nach 30 min, keine Entfernung der gerade sichtbaren Card.
- `CardBuilder` / `TriagePolicy`: Card-Reihenfolge, Pinning, Trigger nur bei neuen Items.

**Integrationstests:** echter `EKEventStore` im Simulator (Rechte per `xcrun simctl privacy booted grant reminders <bundle-id>`), Round-Trip anlegen → zuordnen → lesen → abhaken.

**UI-Tests:** Onboarding, Quick Add in Serie, Einzeln-Zuordnen, Board per Tap-Fallback.

**Manuelle Testmatrix vor Release:** geteilte iCloud-Liste mit zweiter Apple-ID (einmal ohne Marqet) · Siri-Eingabe bei offener App · Mac-Reminders ändert eine Notiz · Dark Mode · Dynamic Type AX5 · VoiceOver kompletter Flow · DE/EN · Gerät ohne Apple Intelligence · Kauf/Restore/Familienfreigabe (Sandbox).

---

## 12. Umsetzungsplan

| Meilenstein | Inhalt | Definition of Done |
|---|---|---|
| **M0 Spike** | Risiken klären (siehe unten), Wegwerf-Code | Jede Frage mit Ja/Nein + Notiz beantwortet |
| **M1 Fundament** | Xcode-Projekt, MarqetKit, Core + Tests, EventKitGateway, Mock | Alle Core-Tests grün, Round-Trip-Integrationstest grün |
| **M2 Hauptscreen** | **Spread-fähiger** Pager (1–4 Plätze, Anker, Falz-Ausrichtung), Cards, Abhaken + Undo, Quick Add + Chipleiste, Erledigte, Kontextmenüs, **Laden-Lebenszyklus**, **Card „Weitere Läden“** | Täglich nutzbar mit manuell gesetzten Markern; Planen (erst Läden, dann Items) funktioniert |
| **M3 Kategorien** | Wörterbuch DE/EN (≈ 2.500 Begriffe), `CategoryClassifier`, Abschnitte in Cards, Korrektur per Menü/Drag, Standard-Reihenfolge + manuelle Abschnitts-Sortierung | Goldset ≥ 90 % korrekt ohne KI |
| **M4 Zuordnen** | Trigger, Prompt, Einzeln, Board, Tap-Fallback, gelernte Vorschläge (Free) | Kompletter Flow mit 20 Items < 30 s |
| **M5 Onboarding & Einstellungen** | Katalog, Laden hinzufügen (Katalog/Eigener), Laden-Verwaltung, Umbenennen/Löschen mit Marker-Rewrite | Neuinstallation → nutzbar ohne Erklärung |
| **M6 Pro-Intelligenz** | Auto-Zuordnung, Foundation Models (Laden + Kategorie), Keyword-Fallback, Laufweg auf Kategorie- und Item-Ebene | Hit-Rate KI auf Testset ≥ 80 %; Laufweg nach 2 simulierten Einkäufen stabil |
| **M7 Kauf** | StoreKit 2, Paywall, Gates, Upsell | Sandbox-Kauf, Restore und Familienfreigabe funktionieren |
| **M8 Launch-Reife** | A11y, Lokalisierung, Performance, Icon, Screenshots, Datenschutz/Support-Seite, TestFlight | TestFlight-Beta mit ≥ 5 Haushalten, 0 Crash-Cluster |

**M0 – Spike-Fragen**
1. Übersteht `🛒 Aldi` in den Notizen den iCloud-Sync zu Reminders auf iPhone und Mac und in eine geteilte Liste unverändert?
2. Lesen und schreiben wir Listen vom Typ „Einkaufsliste“ (mit automatischen Abschnitten) ohne Nebenwirkungen?
3. Funktioniert Multi-Item-Drag (iOS 26 SwiftUI) aus einer Liste in Drop-Zonen innerhalb eines Sheets zuverlässig?
4. Qualität und Latenz von Foundation Models für „deutsches Item → Laden“ bei 10 Items im Batch?
5. Verhalten von horizontalem Pager + vertikaler Liste + Inline-Textfeld mit Tastatur (Scroll-Konflikte, Keyboard-Avoidance)?
6. Bleibt die Tastatur offen, wenn der Pager beim Wechsel über die Chipleiste zu einer anderen Card springt und der Fokus in eine neue Eingabezeile wandert?
7. **iPhone Duo:** die acht Fragen aus [KONZEPT-DUO-IPAD.md §9](KONZEPT-DUO-IPAD.md), vor allem die Anker-Seite und die Falz-Region innen quer.

*Befunde aus dem M1-Klicktest, in M2 beheben:* Nach Return darf das Eingabefeld den Fokus nicht abgeben, sonst gehen bei schneller Serien-Eingabe Zeichen verloren. Bei offener Tastatur darf der erste Tipp auf den Abhaken-Kreis nicht verschluckt werden.

---

## 13. Versionsplan: was wann kommt

| Version | Thema | Inhalt | Warum hier |
|---|---|---|---|
| **v1.0** | **MVP** | Alles in diesem Dokument ohne Kennzeichnung „v1.x“: Marker, Pager, Zuordnen (Einzeln/Board), **Kategorien**, **Laden-Lebenszyklus**, **Card „Weitere Läden“**, **Chipleiste**, Katalog + eigene Läden, Pro-Intelligenz inkl. Laufweg, StoreKit | Validiert den Kern. Die neuen Wünsche sind UX-Kern mit geringer bis mittlerer Komplexität und ohne neue Berechtigungen |
| **v1.1** | **Schneller** | App Intents/Siri („Füge Milch bei Aldi hinzu“, „Was brauche ich bei dm?“) · interaktive Widgets · `@Laden`-Syntax in der Eingabe · Hinweis „Meist bei Rewe – verschieben?“ · **Prospekt-Link** pro Kette · Katalog-Updates als statisches JSON vom CDN (ohne Nutzerdaten) | Kleine, unabhängige Features mit hohem Alltagsnutzen |
| **v1.2** | **Orte** | Filialen, Karte, Laden aus der Karte anlegen, Laden-Sortierung nach Entfernung und „Smart“ (14.1, 14.2) | Neue Standort-Berechtigung, POI-Qualität, Ketten-Erkennung und Rate-Limits: eigenes Release mit eigenem Testfokus |
| **v1.3** | **Unterwegs** | Einkaufsrunde mit Routenoptimierung (14.3) · Standort-Hinweis „Du bist bei Aldi“ · Apple Watch · Live Activity „Einkaufsmodus“ | Baut auf den Filialen aus v1.2 auf |
| **v2.0** | **Angebote** | Angebots-Treffer zur Liste, Angebot → Liste, Opt-in mit PLZ (siehe [MARKTANALYSE.md](MARKTANALYSE.md) §3) | Braucht einen Partnervertrag, der Reichweite voraussetzt (Gates G1–G4) |
| **v2.x** | **Sparen & Ausbau** | Einkauf optimieren (Angebote × Entfernung × Menge) · mehrere Listen · Mac · iPad-Sidebar · geteilte Laden-Konfiguration per CloudKit-Sharing · eigene Kategorie-Sets für Drogerie und Baumarkt | Hängt von Angebotsdaten und Nutzerfeedback ab |

---

## 14. Ausblick-Spezifikation: Orte & Routen (v1.2 / v1.3)

Diese Spezifikation wird jetzt schon festgehalten, damit das Datenmodell in v1.0 passt.

### 14.1 Filialen & Karte (v1.2)

- **Berechtigung:** Standort „Beim Verwenden“, optional. Ohne Standort funktioniert alles wie in v1.0.
- **Filialen finden:** Für jeden eigenen Laden mit `mapSearchTerms` sucht `MKLocalSearch` (Region ~10 km um den Nutzer, `resultTypes = .pointOfInterest`, POI-Filter passend zum Ladentyp: `.foodMarket`, `.store`, `.pharmacy`, `.bakery` …). Treffer werden über die normalisierten Aliase der Kette zugeordnet.
- **Persistenz:** `MKMapItem.identifier` wird in `StoreLocation.mapItemIdentifier` gespeichert, das Nachladen läuft über `MKMapItemRequest`. Die Koordinaten liegen nur lokal bzw. im privaten iCloud.
- **Bevorzugte Filiale** pro Laden: vom Nutzer gewählt, sonst die nächstgelegene.
- **Kartenansicht** (Toolbar-Button → Vollbild-Sheet): Pins in Laden-Farbe mit der Anzahl offener Items, blasse Pins für Katalog-Ketten in der Nähe, die noch nicht angelegt sind („Rewe – hinzufügen?“), dazu ein Bottom Sheet mit der Laden-Liste (Entfernung, offene Items).
- **Laden aus der Karte anlegen:** Suchfeld (`MKLocalSearchCompleter`) → POI wählen → Kette erkannt → Katalog-Laden + Filiale. Nicht erkannt → eigener Laden, Typ aus der POI-Kategorie abgeleitet.
- **Rate-Limits:** MapKit-Suchen werden gedrosselt. Ergebnisse werden pro Laden und Region 24 h gecacht und nur bei einer Ortsänderung > 2 km neu gesucht.
- **Öffnungszeiten** liefert MapKit öffentlich nicht, deshalb werden sie nicht berücksichtigt.
- **Datenschutz:** Anfragen gehen nur an Apple (MapKit). Ziel bleibt das Label „Keine Daten erfasst“; vor Release gegen die aktuellen App-Store-Richtlinien prüfen.

### 14.2 Laden-Sortierung (v1.2)

Modi in den Einstellungen: **Manuell** (Standard) · **Entfernung** · **Smart**. `Unsortiert` bleibt immer vorne, `Weitere Läden` immer hinten.

- **Entfernung:** Anfahrtszeit zur bevorzugten bzw. nächsten Filiale. Läden ohne Filiale folgen am Ende in manueller Reihenfolge.
- **Smart:** `score = n / (t + 5)`, wobei `n` die offenen Items sind, `t` die Anfahrtsminuten und `5` eine Pauschale pro Stopp (Parken, Kasse). Sortiert wird absteigend. Der Card-Header zeigt dann „8 Artikel · 6 min“. Geplante leere Läden (n = 0) stehen hinter allen aktiven.
- `t` kommt aus einer `MKDirections`-ETA (15 min Cache). Fallback ist die Luftlinie mit einer Durchschnittsgeschwindigkeit je Verkehrsmittel (Einstellung: Auto / zu Fuß).
- **Stabilität:** Neu sortiert wird nur beim Öffnen der App bzw. per Pull-to-Refresh, nie während die Cards sichtbar sind.

### 14.3 Einkaufsrunde (v1.3)

- **Einstieg:** „Runde planen“ (Karte oder Toolbar), sobald ≥ 2 aktive Läden eine Filiale haben.
- **Auswahl:** Läden (vorausgewählt: alle aktiven mit Filiale), Start = aktueller Standort, Ziel = zurück zum Start oder offenes Ende.
- **Optimierung:** exaktes TSP per Permutation bei n ≤ 7 Stopps (≤ 5.040 Reihenfolgen, trivial). Erst eine Luftlinien-Matrix für die Vorauswahl der Top 3, dann echte `MKDirections`-ETAs nur für diese Kandidaten (schont die Rate-Limits).
- **Kategorie-Regel:** Läden mit Items aus **Tiefkühl** (und optional Kühlware) werden ans Ende der Runde gelegt. Das ist ein Vorteil, den nur Marqet mit seinen Kategorien bieten kann.
- **Ergebnis:** Karte mit nummerierten Pins, Gesamtzeit, Items pro Stopp → „In Apple Maps starten“ über Unified Maps URLs (Richtungen mit wiederholbaren Wegpunkten, ab iOS 18.4; im v1.3-Spike verifizieren). Fallback: Navigation Etappe für Etappe per `MKMapItem.openMaps`.
- **Während der Runde:** Der Pager folgt der Routen-Reihenfolge (Banner „Runde aktiv“). Ist eine Card erledigt, erscheint „Weiter zu dm (4 min)“.
- **Standort-Hinweise (opt-in):** `CLMonitor` überwacht die bevorzugten Filialen von Läden mit offenen Items (max. 20 Regionen). Beim Betreten kommt eine lokale Mitteilung „Du bist bei Aldi – 5 Artikel offen“. Dafür ist die Standortfreigabe „Immer“ nötig, sie wird separat und begründet angefragt.

---

## 15. Offene Punkte außerhalb der Technik

- Markenrecherche „Marqet“ (DPMA/EUIPO) und Verfügbarkeit des App-Store-Namens
- Bundle-ID und Developer-Account (Einzelperson oder Firma → Impressum)
- App-Icon und Farbpalette (Design-Sprint vor M8)
- Endgültiger Preis für Pro
- Kategorien-Wörterbuch: Erstellung (KI-gestützt) und Kuratierung von ≈ 2.500 Begriffen DE/EN/AT/CH, eigener Aufwandsblock in M3
- Nach dem Launch: Erstgespräche mit ShopFully (Publisher-Programm) und Bonial (Reach), um Konditionen und Mindestreichweite zu klären
