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
| 4 | Zuordnen-UX | *Rev. 6 (26.09.):* **Nacheinander und Übersicht** mit Umschalter, die Wahl wird gemerkt. **Nacheinander:** Frage „Wo kaufst du das?“, Fortschritt „2 von 12“, Vorschau „Als Nächstes“, darunter die Laden-Kacheln sowie „Später“ und „Laden hinzufügen“. Übersprungene Einträge kommen am Ende noch einmal („Jetzt zuordnen“). **Übersicht:** eine Tabelle wie eine Umfrage, eine Zeile pro Eintrag, eine Spalte pro Laden (iPhone 4, breit 8, der Rest hinter „…“). Ein Tipp ordnet sofort zu, es gibt keine Auswahl mehr. In beiden Modi: „N Vorschläge übernehmen“ als ein Schritt, unten eine Zeile mit dem letzten Schritt („Milch → Rewe“), Rückgängig gilt auch fürs Überspringen |
| 5 | Zusätzliche Cards | **„Unsortiert“-Card vorne**, solange es unsortierte Items gibt |
| 6 | Intelligenz | **Lokales Lernen + Apple Intelligence** (Foundation Models) |
| 7 | Plattform | *Rev. 3:* **iPhone, iPhone Duo und iPad ab v1.0**, iOS 26+, Duo-Funktionen ab iOS 27.1 per `#available`, SwiftUI, Xcode 27 (SDK 27.1) |
| 8 | Geschäftsmodell | **Freemium + Einmalkauf** „Marqet Pro“ |
| 9 | Plus-Button | **Kontextabhängig:** neues Item gehört zum Laden der aktiven Card |
| 10 | Erledigte Items | **Wie Reminders:** Häkchen, nach ~1,5 s ausblenden, „Erledigte anzeigen“ |
| 11 | Zuordnen-Trigger | **Pro: Auto-Zuordnung** sicherer Items. Der Rest wartet in der Unsortiert-Card (Inbox) mit „Läden zuordnen“ als Footer, *keine* Nachfrage per Popover |
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
| 35 | Unsortiert-Card | *Rev. 4:* **Immer sichtbar und direkt nach Prospekte**, auch ohne Einträge (ersetzt #5) |
| 36 | Prospekte-Card | *Rev. 5 (26.09.):* **Erste Card vor Inbox**, zentrale Sammlung offizieller Händler-Prospekte über `leafletURL`; „Weitere Läden“ bleibt letzte Card |
| 36 | Projektdatei | *Rev. 4:* **`project.yml` ist die einzige Quelle**, `scripts/generate.sh` erzeugt das Projekt, `scripts/ci.sh` prüft alles |
| 37 | Name der ersten Card | *Rev. 5 (26.09.):* **„Inbox“** statt „Unsortiert“; „Läden zuordnen“ mittig am Card-Ende |
| 38 | Laden-Vollbild | *Rev. 5:* Tipp auf den Header oder Hochziehen der Liste zoomt die Card auf Vollbild (Zoom-Transition). Plus bleibt, Seitenpunkte fallen weg. Der aktuelle Prospekt steht direkt unter dem Header, ohne zusätzliche Abschnittsüberschrift |
| 39 | Prospekt-Link | *Rev. 5:* **v1.0** (vorgezogen aus #27) im Laden-Vollbild: offizielle Angebotsseite der Kette im `SFSafariViewController`. Einzelangebote bleiben v2.0 (#27) |
| 40 | Zusammenfassung über der Inbox | *Rev. 5 (26.09.):* Beim ersten Laden pro App-Start, wenn Läden offene Einträge haben oder geplant sind: großer Titel und Karte „Was jetzt wichtig ist“ (Läden mit Anzahl, nächster Laden, Inbox) mit „Einkauf starten“ und „Zuordnen“. Die Inbox rutscht darunter, die Seitenpunkte sind ausgeblendet. Wischen zur nächsten Card blendet alles fingergenau aus. Nur iPhone (eine Card). Text aus festen Regeln, nicht vom Sprachmodell – die Zahlen müssen stimmen |
