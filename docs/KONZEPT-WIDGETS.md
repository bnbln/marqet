# Marqet – Widgets, Live-Aktivität und Steuerelemente

Stand: 28.09.2026 (Rev. 9) · Plattform: iOS 26+, neue Größen und Dynamic Island quer ab iOS 27 per `#available`
Gehört zu [KONZEPT.md](KONZEPT.md) (Entscheidungen #46–#53) · Duo & iPad: [KONZEPT-DUO-IPAD.md](KONZEPT-DUO-IPAD.md)

> Marqet ist dort, wo du gerade bist: auf dem Home-Bildschirm als kleine Laden-Card, auf dem Sperrbildschirm
> als laufender Einkauf, im Kontrollzentrum als „Eintrag hinzufügen“ und an der Kasse als Kundenkarte.
> Überall dieselben Objekte, dieselben Farben, dieselben Zahlen wie in der App.

---

## 1. Recherche

### 1.1 Was iOS 27 neu bringt (im SDK 27.1 geprüft)

| Neu | API | Bedeutung für Marqet |
|---|---|---|
| **Extra-large-Widget 4 × 6** auf dem iPhone, füllt eine ganze Home-Seite; Apple zielt damit ausdrücklich auf das Innendisplay des iPhone Duo | `WidgetFamily.systemExtraLargePortrait` (iOS 27) | Eine komplette Einkaufsliste eines Ladens oder das ganze Einkaufs-Dashboard, ohne die App zu öffnen. Auf dem Duo: XL-Widget links, App-Symbole rechts vom Falz |
| **Extra-large auf dem iPad** auch in der Heute-Ansicht | `WidgetFamily.systemExtraLarge` (seit iPadOS 15) | Überblick als Raster aus Mini-Cards |
| **Dynamic Island im Querformat** (kompakt und minimal) | `@Environment(\.isDynamicIslandLimitedInWidth)` | Kompakte Darstellung braucht eine schmale Variante: nur Zahl, kein Ring |
| **Live-Aktivitäten auf Apple Watch, CarPlay, Mac-Menüleiste** | `.supplementalActivityFamilies([.small])`, `@Environment(\.activityFamily)` | Der laufende Einkauf erscheint im Smart Stack der Watch, ohne eigene Watch-App |
| **StandBy** mit Markenfarbe | `@Environment(\.showsWidgetContainerBackground)`, `activityBackgroundTint` | Küchen-/Ladenmodus am Ladegerät |
| **Echtzeit-Updates von Widgets, solange die App offen ist** | `WidgetCenter.reloadTimelines` ohne Budget im Vordergrund | Abhaken in der App ist sofort im Widget |
| **Liquid Glass anpassbar** (klar, getönt) | `widgetRenderingMode == .accented`, `widgetAccentable()`, `widgetAccentedRenderingMode(_:)` | Jede Ansicht muss auch ohne Markenfarben funktionieren (§4.4) |
| **Einkaufsliste in Erinnerungen** in mehr Sprachen, Auto-Kategorien | – | Apples Liste wird besser. Marqets Unterschied bleibt: **Läden** statt Regalen, Kundenkarte, Prospekt, Einkaufsrunde |

Weiter gültig aus iOS 17–26: interaktive Widgets (`Button(intent:)`, `Toggle(isOn:intent:)`), Steuerelemente im Kontrollzentrum, auf dem Sperrbildschirm und auf der Aktionstaste (`ControlWidget`), `LiveActivityIntent` (läuft im App-Prozess), `supportedModes` statt `openAppWhenRun` (iOS 26), `TimelineEntryRelevance` für den Smart Stack.

### 1.2 Was andere machen

| App | Widgets | Lücke, die Marqet füllt |
|---|---|---|
| **Erinnerungen** (Apple) | Liste klein bis XL, abhaken im Widget | Weiß nichts von Läden. Eine Liste = ein Widget, keine Kundenkarte, kein Einkauf |
| **Bring!** | Liste (nur öffnen, kein Abhaken), Kundenkarten-Widget | Keine Läden, nicht interaktiv, keine Live-Aktivität |
| **AnyList / OurGroceries** | Liste, teilweise abhaken | Keine Läden, keine Live-Aktivität |
| **Things / Todoist** | Hochwertige interaktive Listen | Vorbild für Qualität: klare Zeilen, großzügige Trefferflächen, ruhige Leerzustände |

**Fazit:** Niemand verbindet Liste, Laden, Kundenkarte und Einkauf. Das ist Marqets Kern und wird zum roten Faden der Widgets.

---

## 2. Leitlinien

1. **Eine Card, viele Orte.** Jedes Widget ist eine Miniatur der App-Card: Kopf in Markenfarbe, gleiches Laden-Abzeichen, Einträge im Laufweg, dieselben Zahlen. Wer die App kennt, versteht das Widget sofort.
2. **Abhaken ohne App.** Jede sichtbare Zeile mit Kreis lässt sich abhaken. Das Ergebnis ist identisch mit der App: Schreiben in Erinnerungen (Familie sieht es sofort), Laufweg lernt mit, Rückgängig in der App.
3. **Der Einkauf ist eine Live-Aktivität.** Sie beginnt beim ersten Abhaken in einem Laden (oder bewusst), führt von Laden zu Laden und beendet sich selbst.
4. **Kasse = ein Tipp.** Die Kundenkarte ist vom Sperrbildschirm aus erreichbar: in der Live-Aktivität, als Widget und als Steuerelement.
5. **Die Zahlen stimmen immer.** Texte aus festen Regeln, nie vom Sprachmodell (wie bei der Zusammenfassung, KONZEPT #40).
6. **Ruhig.** Keine Streaks, keine Werbung, keine Pro-Hinweise im Widget. Widgets zeigen Zustand, nicht Marketing.
7. **Text braucht die App.** Widgets haben keine Texteingabe. „+“ öffnet die App direkt im Eingabefeld der richtigen Card.

---

## 3. Für jede Liste ein Widget

Anforderung: Zu **jeder Liste in der App** lässt sich ein Widget einrichten.

| Liste in der App | Widget | Einstellung im Widget („Widget bearbeiten“) |
|---|---|---|
| **Inbox** (Einträge ohne Laden) | **Liste** | Liste = Inbox |
| **Jede Laden-Card** (Aldi, dm, Markt …), auch ausgeblendete Läden | **Liste** | Liste = Laden |
| **„Nächster Laden“** – die Card, die gerade dran ist | **Liste** (Standard) | Liste = Automatisch: laufender Einkauf → erster Laden mit Einträgen (in Card-Reihenfolge, also auch nach Entfernung/Smart) → Inbox |
| **Erledigt** (letzte 7 Tage, „Nochmal kaufen“) | **Liste** | Liste = Zuletzt erledigt |
| **Alle Läden** (der Pager) und **Orte** (Läden nach Entfernung) | **Überblick** | Reihenfolge: wie in der App / meiste Einträge / Entfernung · Inbox zeigen · leere geplante Läden zeigen |
| **Angebote** (Prospekte) | **Angebote** | Laden oder „Meine Läden“ |
| **Kundenkarten** | **Kundenkarte** | Karte oder „Automatisch“ (Karte des laufenden bzw. nächsten Ladens) |
| „Weitere Läden“ | – | Keine Liste mit Einträgen; ausgeblendete Läden sind im Listen-Widget wählbar |

Ein Listen-Widget für einen ausgeblendeten Laden zeigt „Noch leer“ mit „+“. Tippt man darauf, wird der Laden geplant und die Card erscheint (wie über „Weitere Läden“).

---

## 4. Widgets im Detail

### 4.1 Größen

| Widget | Klein | Mittel | Groß | XL (iPad) | XL hoch (iOS 27) | Sperrbildschirm |
|---|---|---|---|---|---|---|
| Liste | ✓ | ✓ | ✓ | ✓ | ✓ | rechteckig, rund, Zeile |
| Überblick | ✓ | ✓ | ✓ | ✓ | ✓ | rechteckig, rund, Zeile |
| Kundenkarte | ✓ | ✓ | – | – | – | rechteckig |
| Angebote | ✓ | ✓ | ✓ | – | – | – |

### 4.2 Liste

Aufbau wie die Card: **Kopfband** in Markenfarbe (Verlauf wie in der App, Abzeichen, Name, „9 offen“, Entfernung), darunter die Einträge **im Laufweg**, in Lebensmittel-Läden mit Kategorie-Abschnitten.

| Größe | Inhalt | Aktionen |
|---|---|---|
| Klein | Kopfband, 3 Zeilen, „+ 6 weitere“ | Kreis = abhaken, Rest öffnet die Card |
| Mittel | Kopfband mit „+“, 2 Spalten × 3 Zeilen; Inbox und kurze Listen einspaltig (Vorschlags-Chips brauchen Platz) | abhaken, „+“ öffnet die Eingabe auf dieser Card |
| Groß | Kopfband, Abschnitte mit Kategorie-Symbol, bis 11 Zeilen, Fußzeile „Einkauf starten“ | abhaken, „+“, Einkauf starten (Live-Aktivität) |
| XL hoch | wie Groß mit bis 18 Zeilen in einer Spalte (zwei Spalten wären bei 364 pt zu schmal für die Namen), unten die **Kundenkarte mit Barcode**, falls vorhanden | alles oben plus Kundenkarte öffnen |
| XL (iPad) | Kopfband, bis 24 Zeilen in drei Spalten | wie Groß |
| Sperrbildschirm rechteckig | „Aldi Süd · 9“, zwei nächste Einträge | öffnet die Card |
| Sperrbildschirm rund | Ring (erledigt/gesamt im Einkauf, sonst Anzahl) mit Monogramm | öffnet die Card |

**Inbox-Variante:** grauer Kopf wie die Inbox-Card. Zeilen mit gelerntem Vorschlag tragen rechts einen Chip in Ladenfarbe („→ Rewe“): ein Tipp ordnet zu und lernt mit (Free, KONZEPT #16). Fußzeile „Läden zuordnen“ öffnet das Zuordnen.
**Erledigt-Variante:** Zeilen durchgestrichen, rechts „↺“ = Nochmal kaufen.
**Leerzustände** wie in der App: „Alles erledigt bei Aldi“ (Häkchen-Siegel), „Noch leer – tippe +“, „Alles sortiert“.

### 4.3 Überblick („Einkaufen“)

*Rev. 2 (28.09.):* Jede Größe trägt einen **Kopf in der Marqet-Akzentfarbe** mit dem Wagen des App-Icons, „Einkaufen“ und der Gesamtzahl – wie der farbige Kopf der Listen-Widgets, nur in Marqets eigener Farbe statt in einer Ladenfarbe. So ist das Widget auf den ersten Blick als Marqet erkennbar. Wenig Text: kein Listenname, kein Zusammenfassungssatz, keine „in 4 Läden“-Zeile.

| Größe | Inhalt |
|---|---|
| Klein | Kopf, darunter die Einträge der Läden groß, **Farbleiste** (Segmente in Markenfarben, Breite = Anteil), Inbox als Symbol mit Zahl |
| Mittel | Kopf, darunter der **Mini-Pager:** bis zu vier kleine Cards nebeneinander (Kopf in Markenfarbe, große Zahl, Name), die Inbox zuerst, „+2“ am Ende. Jede Mini-Card öffnet ihre Card, „+2“ öffnet Home |
| Groß | Kopf, Zeilen pro Laden mit Vorschau der ersten Einträge, Anzahl und Entfernung, Inbox-Zeile (Zeile → Inbox, „Zuordnen“ → Zuordnen), Schaltfläche **„Einkauf bei Aldi starten“** mit 16 pt Abstand zu Rand und Liste |
| XL hoch | Kopf plus Raster aus Mini-Cards (2 × 3) **mit abhakbaren Einträgen** – das ganze Einkaufs-Dashboard auf einer Home-Seite |
| XL (iPad) | Kopf plus Raster aus Mini-Cards (4 × 2) mit Einträgen |
| Sperrbildschirm | „23 offen · 4 Läden“ und „Aldi 9 · dm 3 · Rewe 2“; rund: Anzahl mit Wagen; Zeile: „🛒 23 offen · Aldi 9“ |

**Tipp außerhalb einer Card oder Zeile:** genau ein Laden → dessen Card; nur die Inbox → Inbox; sonst **Home** (`marqet://home`), nie die Inbox, nur weil sie vorne steht.

### 4.4 Kundenkarte

| Größe | Inhalt |
|---|---|
| Klein | Karte in ihrer Farbe, oben die Logos der Läden, groß **„Kundenkarte“** (die Marke steht schon im Logo; ohne Laden der Kartenname), maskierte Nummer. Tippen = Vollbild mit maximaler Helligkeit |
| Mittel | Links Farbfeld mit Logos oben und „Kundenkarte“, rechts der **echte Barcode** auf Weiß mit Nummer |
| Sperrbildschirm | Name + „An der Kasse zeigen“ |

Barcode und Nummer sind `privacySensitive()`: Auf dem gesperrten Gerät werden sie verborgen.

### 4.5 Angebote

Prospekt-Cover wie im Regal der Angebote-Card (Markenfarbe, Logo, KW). Klein: ein Cover. Mittel: vier. Groß: sechs in zwei Reihen. Eigene Läden mit Einträgen tragen unten eine ruhige Marke in Ladenfarbe („🛒 9“), keine rote Zahl wie eine Mitteilung. Reihenfolge: eigene Läden mit offenen Einträgen, andere eigene Läden, dann Ketten in der Nähe. Tippen öffnet die offizielle Angebotsseite in der App.

### 4.6 Darstellung

| Modus | Verhalten |
|---|---|
| Farbig (Standard) | Kopfband in Markenfarbe, Text darauf weiß oder schwarz (gelbe Ketten), Kreise in der lesbaren Ladenfarbe (WCAG AA, wie in der App) |
| Klar und getönt (Liquid Glass) | Kein Kopfband, Name und Zahlen `widgetAccentable()`, Logos als einfarbiges Monogramm, Prospekt-Cover als Umriss |
| StandBy / Nacht | Systemgesteuert, Kontrast bleibt durch Umriss-Kreise |
| Dark Mode | Karte `secondarySystemGroupedBackground`, lesbare Ladenfarbe aufgehellt |
| Dynamic Type | Widgets folgen bis XXL, darüber kürzen Zeilen mit `lineLimit(1)`; Anzahl der Zeilen bleibt |
| VoiceOver | Kreis: „Milch abhaken“, Chip: „Hafermilch zu Rewe“, Zeile nennt Notiz und Laden |

---

## 5. Live-Aktivität „Einkauf“

### 5.1 Ablauf

| Schritt | Verhalten |
|---|---|
| **Start automatisch** | Beim **ersten Abhaken in einer Laden-Card**, wenn noch kein Einkauf läuft (Einstellung, Standard an). Wer abhakt, steht im Laden |
| **Start bewusst** | „Einkauf starten“ im Laden-Menü, im großen Widget, als Steuerelement, per Siri |
| **Laden wechseln** | Abhaken in einem anderen Laden setzt den Einkauf dort fort. Ist der aktuelle Laden leer: „Alles erledigt bei Aldi“ und Schaltfläche **„Weiter zu dm (3)“** |
| **Ende** | Alle Läden leer → „Einkauf fertig“, verschwindet nach 10 Minuten. 30 Minuten ohne Abhaken (Einkaufssitzung, KONZEPT §7.2) → veraltet und wird beim nächsten Öffnen beendet. „×“ beendet sofort. Systemgrenze 8 h |
| **Aktualisierung** | Lokal aus der App bei jeder Änderung und aus den Intents (App-Prozess). Kein Server, kein Push |

### 5.2 Darstellung

| Ort | Inhalt |
|---|---|
| **Sperrbildschirm** | *Rev. 2 (28.09.):* Kopf: Abzeichen mit **Fortschrittsring**, „Einkauf bei Aldi Süd“, „4 von 9 erledigt“. Darunter die **nächsten sechs Einträge im Laufweg mit Kreis** (abhaken), drei Reihen à zwei mit mehr Luft (24 pt Zeile, 6 pt Abstand). Rechts **Kundenkarte** (öffnet den Barcode) und „×“. „Danach: dm 3 · Markt 2“ nur bei höchstens vier Einträgen – das System schneidet das Banner bei 160 pt ab |
| **Dynamic Island kompakt** | Links Abzeichen, rechts verbleibende Anzahl mit Fortschrittsring in Markenfarbe |
| **Dynamic Island quer (iOS 27)** | `isDynamicIslandLimitedInWidth`: rechts nur die Zahl, ohne Ring |
| **Minimal** | Ring mit Zahl |
| **Erweitert** | Name und Fortschritt, nächste zwei Einträge mit Kreis, Knöpfe „Kundenkarte“ und „Weiter“ bzw. „Beenden“ |
| **Watch / CarPlay (`.small`)** | Abzeichen, Name, Anzahl, nächster Eintrag mit Kreis |
| **StandBy** | Hintergrund in Markenfarbe (`activityBackgroundTint`) |

### 5.3 Daten (ActivityKit, < 4 KB)

- **Attribute (fest):** Listentitel, Einkaufs-ID.
- **Zustand (dynamisch):** aktueller Laden (Name, Farbe, Symbol, Katalog-Schlüssel), nächste bis zu 6 Einträge (ID, Titel, Notiz), offen, erledigt, bis zu 3 nächste Läden (Name, Farbe, Anzahl), „hat Kundenkarte“, fertig ja/nein.
- Der Laden liegt im **Zustand**, nicht in den Attributen: Die Aktivität begleitet die ganze Runde.

---

## 6. Steuerelemente (Kontrollzentrum, Sperrbildschirm, Aktionstaste)

| Steuerelement | Typ | Einstellung | Wirkung |
|---|---|---|---|
| **Eintrag hinzufügen** | Knopf | Liste (Automatisch, Inbox, Laden) | Öffnet die App mit Tastatur auf der gewählten Card |
| **Kundenkarte** | Knopf | Karte oder Automatisch | Öffnet den Barcode im Vollbild mit voller Helligkeit – ideal auf der Aktionstaste |
| **Einkauf** | Schalter | – | Startet bzw. beendet die Live-Aktivität |

---

## 7. Siri und Kurzbefehle

Die Entitäten für die Widgets (Liste, Laden, Kundenkarte) tragen auch Siri und Kurzbefehle:
„Einkauf bei Aldi starten“, „Kundenkarte zeigen“, „Aldi in Marqet öffnen“, „Eintrag in Marqet hinzufügen“. Alle Sätze enthalten den App-Namen (Apple-Vorgabe). Einträge per Sprache kommen weiter über „Setz Milch auf die Liste Einkaufen“ (Erinnerungen).

---

## 8. Interaktionsmodell

| Geste im Widget | Ziel | Technik |
|---|---|---|
| Kreis | Abhaken | `CheckItemIntent` (`LiveActivityIntent`) |
| Chip „→ Rewe“ | Zuordnen und lernen | `AssignItemIntent` (`LiveActivityIntent`) |
| „↺“ | Nochmal kaufen | `RestoreItemIntent` (`LiveActivityIntent`) |
| „Einkauf starten“ / „Weiter zu dm“ / „×“ | Live-Aktivität | `StartTripIntent`, `NextStoreIntent`, `EndTripIntent` |
| Kopf, Zeile, Mini-Card | Card im Vollbild | `marqet://page/store:<id>` |
| Überblick außerhalb einer Card | Home, nichts geöffnet | `marqet://home` |
| „+“ | Eingabe auf dieser Card | `marqet://compose/store:<id>` |
| „Läden zuordnen“ | Zuordnen | `marqet://triage` |
| Kundenkarte | Barcode im Vollbild | `marqet://card/<id>` |
| Prospekt | Angebotsseite | `marqet://offers/<kette>` |

**Warum alle Aktionen im App-Prozess laufen:** `LiveActivityIntent` führt die Aktion in der App aus (bei Bedarf im Hintergrund gestartet). So gibt es genau einen Weg für Änderungen – das `AppModel` – mit Lernen, Rückgängig, Einkaufssitzung und der Live-Aktivität. Das Widget-Kontingent wird geschont, weil die App danach alle Widgets gezielt neu lädt.

---

## 9. Technik

### 9.1 Ziele und Dateien

| Teil | Ort |
|---|---|
| Datenmodell `WidgetSnapshot`, `WidgetRegistry`, `WidgetSnapshotBuilder`, Deep Links `MarqetLink`, Auswahl „Automatisch“ | `MarqetCore/Widgets` (nur Foundation, getestet) |
| App Group, Speicher, Entitäten, Intents, Widget-Ansichten, Aktivitäts-Attribute | `MarqetShared/` – kompiliert in App **und** Erweiterung, damit die App dieselben Ansichten in der Widget-Galerie zeigt |
| Widget-Erweiterung: Bundle, Timeline-Provider, Live-Aktivität, Steuerelemente | `MarqetWidgets/` |
| Schreiben der Daten, Deep Links, Live-Aktivität steuern, Kurzbefehle, Einstellungen „Widgets“ | `Marqet/App/AppModel+Widgets.swift`, `Marqet/App/Widgets/` |

### 9.2 Datenfluss

1. Die App schreibt bei jeder Änderung (entprellt 0,4 s) in den App-Group-Container:
   - `widget-registry.json`: Konfiguration (Läden, Reihenfolge, Laufweg, gelernte Kategorien und Zuordnungen, Kundenkarten, Prospekte, letzter Standort, Filialen).
   - `widget-snapshot.json`: fertiger Anzeigezustand (Cards in Card-Reihenfolge, Einträge im Laufweg, Vorschläge, Erledigtes, Einkauf).
   Danach `WidgetCenter.reloadAllTimelines()` – nur wenn sich der Snapshot geändert hat.
2. Der Timeline-Provider **liest Erinnerungen selbst** (EventKit in der Erweiterung, Freigabe der App gilt) und baut mit derselben Registry und demselben `WidgetSnapshotBuilder` einen frischen Snapshot. So erscheinen per Siri oder von der Familie hinzugefügte Einträge auch ohne App-Start. Ohne Zugriff: letzter Snapshot.
3. Neuladen: alle 30 Minuten, während eines Einkaufs alle 10 Minuten; `TimelineEntryRelevance` hebt das Listen-Widget im Smart Stack an, solange ein Einkauf läuft.

Ein Weg, eine Wahrheit: App und Erweiterung erzeugen den Snapshot mit **derselben Funktion**. Unit-Tests prüfen Reihenfolge, Abschnitte, Vorschläge und die Auswahl „Automatisch“.

### 9.3 Einstellungen und Rechte

- App Group `group.app.marqet.Marqet` für App und Erweiterung.
- `NSSupportsLiveActivities = YES`, URL-Schema `marqet`.
- Datenschutz-Manifest: zusätzlich UserDefaults-Grund `1C8F.1` (App Group). Label bleibt „Keine Daten erfasst“: nichts verlässt das Gerät.
- Dateischutz `completeUntilFirstUserAuthentication`, damit Sperrbildschirm-Widgets lesen können.
- **Nur die App schreibt** in den Container; die Erweiterung liest. Tests und Vorschauen schreiben nie (`AppModel.sharesWithWidgets`).
- **Händler-Logos ≤ 256 px:** Größere Bilder verwirft die Live-Aktivität stillschweigend (im Simulator geprüft: das 1181-px-Rewe-Logo blieb ein grauer Kreis). Die Logos liegen dafür in einem eigenen Katalog `StoreLogos.xcassets`, den App und Erweiterung teilen.

---

## 10. In der App: „Widgets & Live-Aktivität“

Neue Seite in den Einstellungen:
- **Galerie** aller Widgets mit den echten Daten (dieselben Ansichten wie auf dem Home-Bildschirm) und kurzer Anleitung zum Hinzufügen.
- Schalter **„Live-Aktivität beim Abhaken starten“** (Standard an).
- **„Einkauf jetzt starten“**, solange Läden Einträge haben.
- Im Laden-Menü „…“ und im Laden-Vollbild: **„Einkauf starten“** bzw. „Einkauf beenden“.

---

## 11. Grenzen und bewusste Entscheidungen

- **Keine Texteingabe im Widget** (Systemgrenze) → „+“ öffnet die Eingabe.
- **Kein Rückgängig im Widget** → Rückgängig in der App (Toolbar), „↺“ in „Zuletzt erledigt“.
- **Unbekannte Läden aus geteilten Listen** landen im Widget bis zum nächsten App-Start in der Inbox (erst die App legt erkannte Läden an).
- **Kein Server-Push**, daher keine Aktualisierung der Live-Aktivität durch Änderungen anderer Personen, solange die App nicht läuft.
- **Pro bleibt Intelligenz:** Widgets, Live-Aktivität und Steuerelemente sind Free (#15). Gelernte Vorschläge im Inbox-Widget sind wie in der App Free, KI-Vorschläge erscheinen nur in der App.

---

## 12. Test

| Ebene | Was |
|---|---|
| Paket (`swift test`) | `WidgetSnapshotTests` (20): Card-Reihenfolge, Laufweg und Abschnitte, Vorschläge, ausgeblendete Läden, JSON, Prospekt-Reihenfolge, „Automatisch“, Einkauf (Wechsel, Ablauf, fertig, < 4 KB), Deep Links hin und zurück |
| App-Tests | `WidgetModelTests` (13): Snapshot aus dem Modell, Abhaken verlässt das Widget sofort, Einkauf startet/wandert/endet, Rückgängig, Einstellung aus, Deep Links (Vollbild, versteckter Laden, Eingabe, Zuordnen, Kundenkarte, Warten bis geladen) |
| Bilder | `WidgetRenderTests` rendert 28 Ansichten hell und dunkel als PNG: `TEST_RUNNER_MARQET_WIDGET_RENDER_DIR=/pfad xcodebuild test … -only-testing:MarqetTests/WidgetRenderTests` |
| Simulator (28.09. geprüft) | Widget in der System-Galerie und auf dem Home-Bildschirm mit echten Daten; Abhaken im Widget → Insel zählt runter, Widget lädt neu; Live-Aktivität auf Sperrbildschirm und in der Dynamic Island (kompakt, erweitert), Abhaken aus der Insel, „Weiter zu Aldi Süd“, Tipp auf die Insel öffnet den Laden. Galerie: `-demo -widget-gallery` |
| Gerät (Phase 1) | Abhaken im Widget bei gesperrtem Gerät, Watch Smart Stack, CarPlay, Duo-Innendisplay mit XL-Widget |
