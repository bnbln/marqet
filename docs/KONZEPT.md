# Marqet – MVP-Konzept

Stand: 28.09.2026 (Rev. 9: Widgets, Live-Aktivität, Steuerelemente) · Status: M1–M6 umgesetzt, Widgets vorgezogen
Widgets & Live-Aktivität: [KONZEPT-WIDGETS.md](KONZEPT-WIDGETS.md)
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
| 4 | Zuordnen-UX | *Rev. 6 (26.09.):* **Nacheinander und Übersicht** mit Umschalter, die Wahl wird gemerkt. **Nacheinander:** Frage „Wo kaufst du das?“, Fortschritt „2 von 12“, Vorschau „Als Nächstes“, darunter die Laden-Kacheln sowie „Später“ und „Laden hinzufügen“. Übersprungene Einträge kommen am Ende noch einmal („Jetzt zuordnen“). **Übersicht:** eine Tabelle wie eine Umfrage, eine Zeile pro Eintrag, eine Spalte pro Laden (iPhone 4, breit 8, der Rest hinter „…“). Ein Tipp ordnet sofort zu, es gibt keine Auswahl mehr. In beiden Modi: „N Vorschläge übernehmen“ als ein Schritt, unten eine Zeile mit dem letzten Schritt („Milch → Rewe“), Rückgängig gilt auch fürs Überspringen |
| 5 | Zusätzliche Cards | **„Unsortiert“-Card vorne**, solange es unsortierte Items gibt |
| 6 | Intelligenz | **Lokales Lernen + Apple Intelligence** (Foundation Models) |
| 7 | Plattform | *Rev. 3:* **iPhone, iPhone Duo und iPad ab v1.0**, iOS 26+, Duo-Funktionen ab iOS 27.1 per `#available`, SwiftUI, Xcode 27 (SDK 27.1) |
| 8 | Geschäftsmodell | **Freemium + Einmalkauf** „Marqet Pro“ |
| 9 | Plus-Button | **Kontextabhängig:** neues Item gehört zum Laden der aktiven Card |
| 10 | Erledigte Items | **Wie Reminders:** Häkchen, nach ~1,5 s ausblenden, „Erledigte anzeigen“ |
| 11 | Zuordnen-Trigger | **Pro: Auto-Zuordnung** sicherer Items. Der Rest wartet in der Unsortiert-Card (Inbox) mit „Läden zuordnen“ als Footer, *keine* Nachfrage per Popover. *Rev. 8 (28.09.):* Die Zuordnen-Ansicht öffnet **nie automatisch** – weder beim Start noch nach dem Onboarding –, immer nur durch den Nutzer (Inbox, Zusammenfassung, Widget-Knopf „Zuordnen“) |
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
| 29 | Anker | **v1.0:** Duo Home-Pager: aktive Card rechts, links die echte Vorgänger-Card. iPad Home-Pager: aktive Card links. Der Laden-Zoom zeigt auf breiten Displays Kontext links und Liste rechts |
| 30 | Plus-Button | **v1.0:** System-Toolbar-Item statt eigenem FAB (wird auf dem Duo senkrecht). Long Press = „Hinzufügen zu …“ |
| 31 | Große Displays | **v1.0:** Drag zwischen Cards, zweiseitiges Zuordnen, Sheets links, iPad-Kurzbefehle. **v1.1:** Küchenmodus (Tischhaltung), linke Seite anheften, Drag aus anderen Apps |
| 27 | Angebote | **v2.0**, nur über eine Publisher-Partnerschaft (ShopFully/Offerista oder Bonial). v1.1: Prospekt-Link pro Kette |
| 32 | Händler-Logos | *Rev. 4 (26.09.):* **Echte Logos bleiben**, das Risiko wird getragen (ersetzt #3 „ohne Logos“). Rückfall auf Monogramme per Schalter, Quellen in `ASSET_SOURCES.md` |
| 33 | Umfang v1.0 | *Rev. 4:* **„Orte“ (Filialen, Karte, Sortierung nach Entfernung/Smart) in v1.0** (ersetzt #24/#25), Routen bleiben v1.3 |
| 34 | iCloud-Sync eigener Läden | *Rev. 4:* **v1.1**; v1.0 speichert lokal, Läden werden über die Marker auf jedem Gerät erkannt |
| 35 | Unsortiert-Card | *Rev. 4:* **Immer sichtbar und direkt nach Angebote**, auch ohne Einträge (ersetzt #5) |
| 36 | Prospekte-Card | *Rev. 5 (26.09.), Name siehe #41:* **Erste Card vor Inbox**, zentrale Sammlung offizieller Händler-Prospekte über `leafletURL`; „Weitere Läden“ bleibt letzte Card |
| 36 | Projektdatei | *Rev. 4:* **`project.yml` ist die einzige Quelle**, `scripts/generate.sh` erzeugt das Projekt, `scripts/ci.sh` prüft alles |
| 37 | Name der ersten Card | *Rev. 5 (26.09.):* **„Inbox“** statt „Unsortiert“; „Läden zuordnen“ mittig am Card-Ende |
| 38 | Laden-Vollbild | *Rev. 5, Rev. 10:* Tipp auf den Header oder freie Listenfläche oder Hochziehen der Liste zoomt die Card auf Vollbild (Zoom-Transition). Plus bleibt, Seitenpunkte fallen weg. Im kompakten Layout liegen Ladenname und Untertitel in der nativen Systemleiste; der aktuelle Prospekt ist über „…“ erreichbar. Im breiten Layout liegt er in der Kontextspalte |
| 39 | Prospekt-Link | *Rev. 5:* **v1.0** (vorgezogen aus #27) im Laden-Vollbild: offizielle Angebotsseite der Kette im `SFSafariViewController`. Einzelangebote bleiben v2.0 (#27) |
| 40 | Zusammenfassung über der Inbox | *Rev. 5 (26.09.):* Beim ersten Laden pro App-Start, wenn Läden offene Einträge haben oder geplant sind: großer Titel und Karte „Was jetzt wichtig ist“ (Läden mit Anzahl, nächster Laden, Inbox) mit „Einkauf starten“ und „Zuordnen“. Die Inbox rutscht darunter, die Seitenpunkte sind ausgeblendet. Wischen zur nächsten Card blendet alles fingergenau aus. Nur iPhone (eine Card). Text aus festen Regeln, nicht vom Sprachmodell – die Zahlen müssen stimmen |
| 41 | Name der Prospekte-Card | *Rev. 7 (28.09.):* **„Angebote“** statt „Prospekte“ (ersetzt den Namen aus #36). Die Card wächst ab v2.0 ohne Umbenennung von Prospekten zu Einzelangeboten (#27). Das einzelne Heft heißt weiter „Prospekt“ („Aktueller Prospekt“ im Laden-Vollbild). Code-Namen (`BrochuresCard`, `PageID.brochures`) bleiben |
| 42 | Kundenkarten | *Rev. 7 (28.09.):* **v1.1, Free.** Karten per Kamera scannen und Läden zuordnen, eine Karte kann für mehrere Ketten gelten (Payback). Anzeige **im Laden-Vollbild** statt in einem eigenen Menü wie bei Bring!: Die Karte des aktuellen Ladens liegt dort, wo man an der Kasse steht. Details in §2 |
| 43 | Systemleiste auf Markenfarbe | *Rev. 8 (28.09.):* Im kompakten Laden-Vollbild übernehmen Toolbar-Buttons und Statusleiste die helle oder dunkle Variante passend zur Markenfarbe (`toolbarColorScheme`), wie die Header-Schrift: weiß auf Aldi-Blau oder Rewe-Rot, schwarz auf Edeka- oder Netto-Gelb. Die Inbox (grau) nutzt die dunkle Variante |
| 44 | Onboarding-Raster | *Rev. 8:* Jeder Schritt nutzt dasselbe Raster: Bildbühne 300 × 184, Überschrift mit immer zwei reservierten Zeilen, darunter Text. Der Abstand nach oben hängt nur von der Bildschirmhöhe ab, deshalb stehen Bild, Überschrift und Textanfang auf allen Seiten gleich hoch. Duo aufgeklappt: Bild links, Text und Button rechts vom Falz. Die Willkommensseite zeigt in einer Schleife, wie drei Einträge aus einer Liste in ihre Laden-Cards fliegen; die anderen Schritte haben kleine erklärende Illustrationen. Reduce Motion zeigt den Endzustand |
| 45 | Läden aus dem Onboarding | *Rev. 8:* Gewählte Läden werden **geplant** angelegt und erscheinen sofort als Cards (vorher unsichtbar bis zum ersten Eintrag). Eine offensichtliche Einkaufsliste wird vorausgewählt, „Neue Liste anlegen“ legt keine Dublette an |
| 46 | Einsprechen | *Rev. 9 (28.09.), Rev. 10: iPhone links gegenüber vom Plus, Englisch:* **Mikrofon neben Plus**: Einkäufe samt Laden einsprechen („10 Eier vom Markt, bei Rewe Hackfleisch“). Die Listen bauen sich beim Sprechen animiert auf, danach „Zu deinen Listen hinzufügen?“. Transkription on-device für alle, Lesen mit Apple Intelligence ist Pro (#15). Details in §3 |
| 47 | Widgets | *Rev. 9 (28.09.):* **Vorgezogen aus v1.1, Free.** Vier Widgets: **Liste** (für jede Liste der App konfigurierbar: Nächster Laden, Inbox, jeder Laden, Zuletzt erledigt), **Überblick**, **Kundenkarte**, **Angebote**. Jedes Widget ist eine Miniatur der Card (Kopf in Markenfarbe, Laufweg). Alle Größen inkl. XL hoch (iOS 27) und Sperrbildschirm. Details: KONZEPT-WIDGETS |
| 48 | Abhaken im Widget | *Rev. 9:* Jede Zeile hat einen Kreis zum Abhaken; Inbox-Zeilen zeigen den gelernten Laden als Chip („→ Rewe“), ein Tipp ordnet zu und lernt mit. Kein Rückgängig im Widget – das bleibt in der App, „↺“ in „Zuletzt erledigt“ |
| 49 | Live-Aktivität „Einkauf“ | *Rev. 9:* **Vorgezogen aus v1.3.** Startet automatisch beim ersten Abhaken in einem Laden (abschaltbar) oder bewusst. Der Laden steckt im Zustand, nicht in den Attributen: Die Aktivität wandert mit („Weiter zu dm“), endet, wenn alles erledigt ist oder nach 30 Minuten ohne Abhaken. Kundenkarte als Knopf auf dem Sperrbildschirm |
| 50 | Ein Weg für Änderungen | *Rev. 9:* Alle Knöpfe in Widgets, Live-Aktivität und Steuerelementen sind `LiveActivityIntent`s und laufen im App-Prozess über das `AppModel` – mit Lernen, Einkaufssitzung und Rückgängig. Die Erweiterung liest nur |
| 51 | Daten für Widgets | *Rev. 9:* Die App schreibt Registry und Snapshot in die App Group; die Erweiterung liest Erinnerungen selbst und baut mit **derselben Funktion** (`WidgetSnapshotBuilder`) neu – Siri-Einträge erscheinen ohne App-Start |
| 52 | Steuerelemente | *Rev. 9:* Kontrollzentrum, Sperrbildschirm, Aktionstaste: „Eintrag hinzufügen“ (öffnet die Eingabe), „Kundenkarte“, Schalter „Einkauf“ |
| 53 | Deep Links | *Rev. 9:* `marqet://` mit `page`, `compose`, `triage`, `completed`, `card`, `offers`, `trip`. Kommen sie vor dem Laden der Liste, warten sie |
| 54 | Widget-Galerie in der App | *Rev. 9:* Einstellungen › „Widgets & Live-Aktivität“ zeigt alle Widgets mit den eigenen Listen (dieselben Ansichten wie auf dem Home-Bildschirm) und den Schalter für den automatischen Start |

---

## 2. Kundenkarten (v1.1)

**Idee:** Bring! legt Kundenkarten in ein Menü neben der Liste. Marqet kennt den Laden, in dem man gerade einkauft, und zeigt deshalb **die passende Karte im Laden-Vollbild**. An der Kasse ist das ein Tipp statt Suchen.

### 2.1 Ablauf

| Schritt | Verhalten |
|---|---|
| Anlegen | Im kompakten Laden-Vollbild über „…“, im breiten Layout über die Kontextspalte oder in den Einstellungen unter „Kundenkarten“. Kamera-Scan (VisionKit `DataScannerViewController`), Rückfall: Nummer und Barcode-Typ von Hand |
| Zuordnen | Beim Anlegen aus dem Laden-Vollbild ist der Laden vorgewählt. Mehrfachauswahl für Programme über mehrere Ketten (Payback). *Offen:* Der Katalog schlägt bekannte Programme vor (`loyaltyPrograms` pro Kette, per Katalog-Update pflegbar, weil Partner wechseln) |
| Zeigen (kompakt) | *Rev. 7b, Rev. 10:* iPhone, Duo außen und schmale iPad-Fenster: **Laden-Icon, Name und Untertitel** stehen links in der nativen Systemleiste, rechts nur [Menü · Schließen]. Das Menü enthält Prospekt, vorhandene Kundenkarten und „Kundenkarte hinzufügen“. Die Liste beginnt direkt unter der Systemleiste. Barcode im Vollbild, **Bildschirmhelligkeit auf Maximum**, beim Schließen zurück. Mehrere Karten: seitlich wischen |
| Zeigen (breit) | iPad und Duo innen: Prospekt und Kundenkarten als Zeilen in der linken Kontextspalte, die Liste rechts bleibt stehen |
| Home-Pager | Keine Karten auf den Laden-Cards, der Pager bleibt ruhig. Die Karte gehört zum Einkauf im Laden, also zum Vollbild |

### 2.2 Technik

- **Modell `LoyaltyCard`** (SwiftData, `MarqetSchemaV2` mit Lightweight-Migration ab V1; die Layouts vor V1 sind als `MarqetSchemaV0` registriert): `id`, `name`, `payload` (Barcode-Inhalt), `symbology`, `colorKey`, `storeIDs` (eigene Läden und Katalog-Ketten). Sync über iCloud zusammen mit den eigenen Läden (E4).
- **Barcode zeichnen:** Code 128, QR, PDF417 und Aztec über Core Image. EAN-13/EAN-8 zeichnet `EANBarcode` in `MarqetCore` selbst (Prüfziffer, Paritäten, getestet), mit Ruhezone links 11 und rechts 7 Module.
- **Typ-Erkennung beim Tippen:** gültige EAN-13/EAN-8 → EAN, sonst Code 128; der Scan liefert den Typ direkt, eine manuelle Wahl gewinnt.
- **Kein Wallet-Import:** PassKit gibt fremde Pässe nicht heraus. Ein Export in Wallet bräuchte einen signierten Pass vom Server, das ist nicht geplant.
- **Payback-Coupons:** Keine offene Schnittstelle. Höchstens ein Absprung in die Payback-App, falls installiert.

### 2.3 Datenschutz & Umfang

- Kartennummern sind personenbezogen, bleiben aber auf dem Gerät bzw. in der eigenen iCloud. Das Privacy-Label bleibt „Keine Daten erfasst“.
- **Free:** Kundenkarten sind keine Intelligenz (#15), sie machen die App im Laden unverzichtbar und gehören deshalb allen.

---

## 3. Einsprechen (v1.1)

**Idee:** Wer vor dem Kühlschrank steht, denkt in Sätzen, nicht in Einträgen: *„Ich brauche 10 Eier und will sie auf dem Markt kaufen, genau wie Suppengrün und 500 g Kartoffeln mehligkochend. Bei Rewe will ich 500 g Hackfleisch kaufen. Ah, und ich brauche Zwiebeln vom Markt.“* Marqet macht daraus in einem Schritt fünf Einträge auf zwei Listen. Der Nutzer sieht dabei zu, wie die Listen entstehen.

### 3.1 Einstiege

| Ort | Verhalten |
|---|---|
| Home | Glas-Button **Mikrofon**. *Rev. 10:* auf dem iPhone **unten links, gegenüber vom Plus** (Daumen links, Seitenpunkte dazwischen). Auf dem iPad direkt links neben dem Plus (gemeinsamer `GlassEffectContainer`). Einträge ohne Laden: Gedächtnis, sonst Inbox |
| Eingabeleiste | Bei leerem Textfeld wird der Senden-Button zum **Mikrofon** (wie in Nachrichten). Einträge ohne Laden gehen in den Laden der Zielkarte (#9) |
| Laden-Vollbild | Über dieselbe Eingabeleiste. Der Diktat-Screen öffnet sich über dem Vollbild |
| Duo | „Einsprechen“ als Item der Systemleiste neben „Hinzufügen“ |

### 3.2 Ablauf aus Nutzersicht

1. **Zuhören.** Vollbild, oben das Transkript in großer Schrift. Erkannte Läden leuchten in ihrer Markenfarbe, erkannte Artikel und Mengen stehen in voller Stärke, Füllwörter bleiben grau, der noch unsichere Rest ist hell. Unten der Stopp-Button, dessen Halo mit der Stimme atmet. Das Umgebungslicht nimmt die Farbe des zuletzt genannten Ladens an.
2. **Listen entstehen.** Nennt der Nutzer „Rewe“, fliegt die Rewe-Karte ein (Header wie im Pager: Logo, Markenfarbe, Zähler). Jeder erkannte Artikel gleitet als Zeile hinein. Die Karte des gerade besprochenen Ladens ist hervorgehoben und wird in Sicht gescrollt. Korrigiert sich die Zuordnung, **wandert die Zeile** sichtbar in die andere Karte (`matchedGeometryEffect`). Mit Apple Intelligence sind noch unbestätigte Zeilen leicht blass und werden kräftig, sobald das Modell sie bestätigt.
3. **Nachfragen.** Nach „Fertig“ bleibt alles stehen, der Titel wird zu **„Zu deinen Listen hinzufügen?“** mit „5 Einträge für 2 Listen“. Tippen wählt ab (durchgestrichen), Kontextmenü: „Laden ändern“ (Zeile fliegt um) und „Entfernen“. Unten „Weitersprechen“ (Mikrofon, hängt an) und „5 Einträge hinzufügen“.
4. **Hinzufügen.** Ein Schritt, **ein Rückgängig** für alles. Neue Katalog-Ketten („Neuer Laden – wird angelegt“) werden geplant angelegt. Der Pager springt zur ersten betroffenen Karte, Haptik „Erfolg“.

Abbrechen mit ✕: Sind Einträge erkannt, fragt Marqet „Diktat verwerfen?“. Wird nichts erkannt, zeigt die Nachfrage einen Leerzustand mit „Nochmal“ über das Mikrofon.

### 3.3 Technik

```
Mikrofon ─ AVAudioEngine ─▶ SpeechAnalyzer (on-device)
                               SpeechTranscriber (.progressiveTranscription)
                               ↳ Rückfall DictationTranscriber
                               AnalysisContext: Ladennamen als Vokabular
          ─ Pegel ─▶ Halo / Umgebungslicht
Transkript (final + volatil)
   ├─ sofort, bei jeder Änderung ─▶ VoiceRuleParser (MarqetCore) ──┐
   └─ nach Satzende (150 ms) / Pause (1,1 s), Pro ─▶               ├─▶ VoiceDraft.merge ─▶ Gruppen ─▶ UI
      FoundationModels streamResponse, Guided Generation ─────────┘
Stopp ─▶ finalizeAndFinish ─▶ letzter Modell-Durchlauf ─▶ Nachfrage ─▶ AppModel.addItems (ein Undo)
```

- **Transkription** (`LiveTranscriber`): `SpeechAnalyzer` mit `SpeechTranscriber`, wo verfügbar, sonst `DictationTranscriber`. Das Sprachmodell wird bei Bedarf über `AssetInventory` geladen (Fortschritt im Screen). Die Audioaufnahme wird per `AVAudioConverter` ins Analyseformat gewandelt, der Tap läuft außerhalb des Main Actors. Die Namen der eigenen Läden und der Katalog-Ketten gehen als `contextualStrings` an den Erkenner.
- **Regeln** (`VoiceRuleParser`, getestet): Sätze an `.!?;`, Teilsätze an Kommas, Doppelpunkten und Bindewörtern („und“, „sowie“, „genau wie“, „as well as“). *Rev. 10:* Woher der Laden eines Artikels kommt, in dieser Reihenfolge:
  1. aus dem eigenen Teilsatz („Zwiebeln vom Markt“),
  2. aus einem anderen Teilsatz desselben Satzes, zuerst dem davor („10 Eier, die will ich auf dem Markt kaufen“),
  3. aus dem **nächsten Satz, wenn der nur einen Laden nennt** („Ich brauche Milch. Die hole ich bei Rewe.“). Das deckt auch Punkte ab, die der Transkribierer bei Sprechpausen mitten in einen Gedanken setzt,
  4. aus dem **Satz davor**, wenn dieser Satz ihn fortsetzt („Und Butter.“, „Außerdem Käse.“, „Genau wie Suppengrün.“) oder eine reine Aufzählung ohne Verb ist („Bei Rewe Milch. Butter. Käse.“). „Ich brauche noch Zahnpasta.“ ist ein neuer Gedanke und übernimmt keinen Laden,
  5. aus einem **vorab angekündigten Laden** („Bei Rewe brauche ich einiges. Milch, Butter.“), bis ein anderer genannt wird.

  Weitere Regeln: Präpositionen („auf dem“, „vom“, „bei“) und Füllwörter fallen weg. Mengen: Ziffern, Zahlwörter, Einheiten („500 g“, „ein Kilo“, „2 Packungen“), auch nachgestellt. Ein kleingeschriebener Teilsatz („…, mehligkochend“) beschreibt den Artikel davor.
- **Sprachmodell** (`DictationInterpreter`, Pro): `DynamicGenerationSchema`, `laden` nur aus den angebotenen Läden oder „keiner“, `greedy`. Gestreamt: Ein Eintrag zählt, sobald sein Laden vollständig ist. Das Modell versteht, was Regeln nicht können: Korrekturen („doch keine Milch“), freie Satzstellung, Namen („Kartoffeln, mehligkochend“). Die Anweisungen gibt es auf Deutsch und Englisch, mit denselben Regeln für Nachbarsätze. *Schutz gegen Erfundenes (Rev. 10):* Im Test hat das Modell Details aus dem Prompt-Beispiel übernommen („Potatoes, floury“, „2 lb“ → „2 kg“). Deshalb sind die Beispiele jetzt neutral, und der Prompt verbietet Umrechnen und erfundene Eigenschaften. Im Code gilt zusätzlich: Ein Eintrag ohne gesprochenes Wort fällt weg, ein Zusatz nach dem Komma bleibt nur, wenn er gesagt wurde.
- **Zusammenführen** (`VoiceDraft`, getestet): Die Identität eines Eintrags ist sein Name aus Buchstaben und Ziffern. So bleiben Zeilen stehen, wenn das Modell die Schreibweise verfeinert. Das Modell entfernt nur, was es in *seinem* Transkript-Stand nicht mehr findet. Regeln entfernen nie, was das Modell bestätigt hat. **Ein im eigenen Satz ausdrücklich genannter Laden schlägt die Vermutung des Modells**: Im Test hat das On-Device-Modell „Kartoffeln“ vereinzelt dem Rewe des Folgesatzes zugeschlagen. Nutzer-Entscheidungen (Abwählen, Laden ändern) schlägt kein Durchlauf.
- **Ziel pro Eintrag** (`AppModel.placement`): gewählt → gesprochen (eigener Laden oder Katalog-Kette) → Zielkarte der Eingabeleiste → Gedächtnis (`SuggestionEngine`, Symbol ↺) → Inbox.
- **Titel** in Erinnerungen: Menge zuerst („500 g Kartoffeln, mehligkochend“). `ItemKeyNormalizer` entfernt die Menge fürs Lernen wieder.

### 3.4 Sprachen

*Rev. 10:* **Deutsch und Englisch.** Maßgeblich ist die App-Sprache, also die der Oberfläche. Die Region des Nutzers bleibt erhalten („en-GB“, „de-AT“). Sie steuert den Erkenner (`SpeechTranscriber`-Locale), die Anweisungen des Modells und zwei Grammatik-Regeln: Kleingeschriebene Zusätze hängen nur im Deutschen am Artikel davor (dort sind Nomen großgeschrieben), und „also“ leitet nur im Englischen eine Fortsetzung ein. Der Wortschatz der Regeln ist gemeinsam, weil viele gemischt sprechen: Füllwörter, Zahlwörter („zehn“, „a dozen“), Einheiten („Pfund“, „lb“, „oz“, „2 cans of“). Die allgemeinen Läden im Katalog kennen englische Namen als Alias („Market“, „Bakery“, „Butcher“, „Drugstore“ …). Angezeigt werden sie weiter unter dem deutschen Namen.

### 3.5 Free, Pro, Datenschutz

- **Free:** Einsprechen mit Regeln. Das deckt die üblichen Formulierungen ab und ist sofort da.
- **Pro:** zusätzlich Apple Intelligence (#15): Korrekturen, freie Sätze, schönere Namen. Das Funkeln oben rechts pulsiert, solange das Modell mitliest.
- Audio und Text bleiben auf dem Gerät, nichts wird gespeichert. Das Privacy-Label bleibt „Keine Daten erfasst“ (#20). Berechtigungen: Mikrofon (`NSMicrophoneUsageDescription`), Spracherkennung (`NSSpeechRecognitionUsageDescription`, vorsorglich).
- **Bedienungshilfen:** Reduce Motion ersetzt Flug- und Skalier-Animationen durch Überblenden, der Halo entfällt. Zeilen melden „ausgewählt“ an VoiceOver.

### 3.6 Offen

- Siri / App Intent „Einkäufe einsprechen“ (#19) auf demselben Parser.
- Namen der allgemeinen Katalog-Läden lokalisieren („Market“ statt „Markt“ in der englischen App). Der Name ist zugleich Marker in den Erinnerungen, das braucht deshalb ein eigenes Konzept.
- Beim Einsprechen genannte Kategorien („beim Metzger um die Ecke“) als eigener Laden anlegen.
- Test auf echtem Gerät: Latenz des Modell-Durchlaufs pro Satz, Erkennungsqualität von Ladennamen mit `contextualStrings`.

## 4. Shopping jenseits von Lebensmitteln

Die Einkaufsliste bleibt der Ausgangspunkt: Auf Home und beim Öffnen der Karte stehen zunächst die Läden mit offenen Einträgen. Der Laden ist ein frei wählbares Ziel für eine Liste, unabhängig davon, ob er Lebensmittel, Kosmetik, Kleidung oder Möbel verkauft. Für bekannte Ketten gibt es einen kuratierten DACH-Katalog mit Suchnamen und Ladentyp. Für jedes andere Geschäft kann der Nutzer einen eigenen Laden mit Namen, Art, Farbe und Symbol anlegen.

Im Kartenfilter wechselt „Alle Läden“ zur Entdeckung. Wählbar sind Lebensmittel, Beauty und Drogerie, Kaufhäuser, Mode und Schuhe, Wohnen und Baumarkt, weitere Geschäfte sowie alle Geschäfte. Die Umgebungssuche nutzt Apple Maps; die Freitextsuche findet auch gezielt benannte Läden und Adressen. Ein Treffer kann als Laden mit bevorzugter Filiale übernommen werden. Die Karte zeigt Vorschläge aus dem Katalog und Orte ohne Katalogeintrag, damit der Katalog keine Grenze für die Nutzerliste bildet.

Apple Maps ist eine Suche nach Points of Interest mit begrenzten Treffermengen, keine vollständige oder garantiert aktuelle Datenbank aller Geschäfte. Deshalb bleibt die manuelle Anlage immer verfügbar. Auf Home dient die Karte der Orientierung und erhält Abstand zu den schwebenden Aktionen. Die Filialkarte zeigt Adresse, Distanz, Listenanzahl, Card und Route; bei „Deine Filiale“ entfällt die Artikelvorschau.
