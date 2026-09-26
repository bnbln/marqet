# Marqet – Soll-Ist-Vergleich und Plan

Stand: 26.09.2026 · Grundlage: deine Anforderungen (Chat), [KONZEPT.md](KONZEPT.md), [KONZEPT-DUO-IPAD.md](KONZEPT-DUO-IPAD.md), [MARKTANALYSE.md](MARKTANALYSE.md) sowie der Code auf `main` (Commit `2c99e7b`, plus eine vorgemerkte Änderung an `StorePager.swift`).

---

## 1. Kurzfazit

- **Der Kern steht:** Das Fundament und die ersten Meilensteine M1–M6 (Erinnerungen, Laden-Cards, Kategorien, Zuordnen, Onboarding, Pro-Intelligenz) sind umgesetzt. **Build-Stand heute:** Das Paket ist grün (85 Tests), die App-Tests haben **4 Fehler von 16**. `AppModelTests` erwarten noch, dass „Unsortiert“ nur bei vorhandenen Einträgen erscheint, die Kern-Tests wurden an die neue Regel (K3) angepasst, die App-Tests nicht. Seit M6 sind dazugekommen: ein globales Rückgängig (auch fürs Löschen), Bearbeiten direkt in der Zeile, Mengen-Tags, Adresse und Info pro Laden, Laden-Sortierung vom Hauptscreen aus, Akzentfarben und Händler-Logos.
- **Bis zum Wunschzustand fehlt viel, aber es ist sehr ungleich verteilt:**
  - **Für den App-Store-Start fehlen vor allem Produktionsthemen:** Kauf, Rechtliches, Datenschutz-Manifest, Englisch, Tests auf echter Hardware.
  - **Deine großen Wünsche** (Karte, Filialen, Entfernung, Routen, Angebote) sind bewusst auf v1.2 bis v2.0 geplant und noch nicht begonnen.
- **Fünf Entscheidungen blockieren den weiteren Weg**, vor allem die Händler-Logos (rechtliches Risiko) und der Umfang von v1.0 (§4).
- **Reihenfolge nach den Entscheidungen vom 26.09.:** stabilisieren → echte Geräte plus MapKit-Spike → Kauf → „Orte“, parallel Launch-Reife und die restlichen v1.0-Lücken → TestFlight → Launch v1.0 mit „Orte“ → „Schneller“ (inkl. iCloud-Sync) → „Unterwegs“ → „Angebote“ (§6).

---

## 2. Soll gegen Ist

Legende: ✅ fertig · 🟡 teilweise · ❌ fehlt · ⚠️ widerspricht dem Konzept (Entscheidung nötig)

### 2.1 Deine ursprünglichen Anforderungen

| Anforderung | Stand | Anmerkung |
|---|---|---|
| Zugriff über die Reminders-API, Zuordnung über die Notizen | ✅ | Zeile `🛒 Laden` in den Notizen, Tests auch mit echtem EventKit |
| Hauptansicht: gewählte Liste, hohe wischbare Laden-Cards | ✅ | 1–4 Cards je Breite |
| Plus unten in der Ecke, Einträge hinzufügen und abhaken wie in Erinnerungen | ✅ | Serien-Eingabe, Abhaken mit Rückgängig |
| Unsortierte Einträge per Drag in Läden ziehen, Nachfrage beim Öffnen, einzeln oder per Drag | ✅ | Zuordnen-Screen mit den Modi Einzeln und Board |
| Marktreif | 🟡 | siehe §3: Kauf, Rechtliches, Englisch, echte Geräte fehlen |
| Andere Apps angeschaut, Angebote per API | ✅ Analyse / ❌ Umsetzung | Angebote nur über eine Partnerschaft (v2.0) |
| Kategorien wie bei Bring! und Erinnerungen | ✅ | ≈ 1.000 Begriffe, Ziel ≈ 2.500 |
| Neue Läden anlegen | ✅ | Katalog, eigene Läden, Adresse als Freitext |
| Karte mit Läden, Routen, Sortierung nach Entfernung oder „Smart“ | ❌ | v1.2 und v1.3 („Orte“, „Unterwegs“) |
| Laden ohne Einträge vom Hauptscreen aus befüllen | ✅ | Card „Weitere Läden“, Chips, Long Press auf Plus |
| Letzte Card zeigt weitere Läden, leere geplante Läden bleiben länger | ✅ | Lebenszyklus nach KONZEPT §7.2 |
| iPhone Duo: aktive Card bleibt rechts, links die Vorgängerin bzw. „Laden hinzufügen“ | 🟡 | Code und Unit-Tests da, **nie auf dem Duo-Innendisplay gesehen** |
| iPad | 🟡 | Mehrere Cards nebeneinander ✅. Kurzbefehle, Zeiger-Effekte und mehrere Fenster ❌ |
| Weitere Ideen fürs Duo (Küchenmodus, linke Seite anheften …) | ❌ | v1.1 |

### 2.2 Konzept v1.0 (KONZEPT §13 und Umsetzungsplan)

| Bereich | Stand | Offen |
|---|---|---|
| M0 Spike (echte Geräte) | ❌ | Kein einziger Punkt auf echter Hardware geprüft: Marker-Sync mit Mac und geteilter Liste, Einkaufslisten-Typ, Duo-Posen, Qualität von Foundation Models |
| M1–M6 | ✅ | siehe README |
| M7 Kauf (StoreKit 2, Paywall, Familienfreigabe) | ❌ | Pro nur über den Debug-Schalter |
| M8 Launch-Reife | ❌ | siehe §3 |
| Laden-Konfiguration per CloudKit auf eigenen Geräten syncen | ❌ | `cloudKitDatabase: .none`, dafür fehlen Developer-Team und iCloud-Container |
| Items innerhalb eines Abschnitts per Drag sortieren (Free) | ❌ | alphabetisch |
| Kategorie-Korrektur per Drag zwischen Abschnitten | 🟡 | nur über das Menü |
| iPad: Kurzbefehle, Zeiger, mehrere Fenster | ❌ | `UIApplicationSupportsMultipleScenes: false` |
| Löschen mit Rückgängig | ✅ | über das globale Rückgängig in der Toolbar (seit `2c99e7b`) |
| Englisch | ❌ | 195 Texte, 0 davon übersetzt |
| Barrierefreiheit (VoiceOver, Dynamic Type AX5, Kontrast) | 🟡 | Teile vorhanden, kein systematischer Audit. Neue lesbare Laden-Farben (4,5:1) sind in Arbeit |

### 2.3 Konflikte zwischen Code und Konzept ⚠️

| # | Konflikt | Risiko | Empfehlung |
|---|---|---|---|
| K1 | **Echte Händler-Logos** (35 Assets, `ASSET_SOURCES.md`). Das Konzept sagt ausdrücklich: keine Logos (KONZEPT §8, MARKTANALYSE §3.3) | **Hoch.** „Public Domain“ auf Wikimedia bezieht sich aufs Urheberrecht, **nicht aufs Markenrecht**. App Review 5.2.1 verlangt Rechte an fremden Marken, in einer kostenpflichtigen App drohen Ablehnung und Abmahnung | Für den Launch zurück zu Monogrammen (die Logik ist noch da). Logos nur mit schriftlicher Freigabe der Händler, z. B. im Zuge der Angebots-Partnerschaft v2.0 |
| K2 | **Eigener schwebender Plus-Button** und eigene Titel-Ansicht oben links. Das Duo-Konzept §3 verlangt System-Toolbar-Items | Mittel. Auf dem Duo-Außendisplay wandern beide nicht in die senkrechte Leiste, die Bedienung mit dem Daumen leidet | Im Duo-Spike prüfen. Wenn es hakt: Plus als `ToolbarItem`, Titel als normaler `navigationTitle` |
| K3 | **„Unsortiert“ ist immer sichtbar**, laut Konzept nur bei > 0 | Gering. Auf dem Duo steht links neben dem ersten Laden dadurch immer „Unsortiert“ statt „Weitere Läden“ | Bewusst so lassen (Eingang ist immer erreichbar) und das Konzept anpassen |
| K4 | **Zwei Quellen für die Projektdatei:** `project.yml` (XcodeGen) und die von Hand gepflegte `project.pbxproj` | Mittel. Ein `xcodegen generate` überschreibt Handänderungen (ist in dieser Sitzung beinahe passiert und wurde zurückgesetzt) | Eine Quelle festlegen, am besten XcodeGen, und die pbxproj generiert und committet |
| K5 | **Mehrere parallele Bearbeiter** am selben Code, ohne Branches oder CI | Mittel | Feature-Branches, CI mit `swift test` und `xcodebuild test`, erst nach grünem Build nach `main` mergen |

---

## 3. Launch-Blocker (ohne sie kein App-Store-Release)

| # | Blocker | Aufwand |
|---|---|---|
| B1 | **Kauf (M7):** StoreKit 2, Einmalkauf, Familienfreigabe, Paywall, Käufe wiederherstellen, Offline-Cache, StoreKit-Testkonfiguration | M |
| B2 | **Händler-Logos** (K1, E1: behalten): Rückfallschalter auf Monogramme, Quellen-Doku für alle 35 Logos, Review-Hinweis | S |
| B3 | **Datenschutz-Manifest** `PrivacyInfo.xcprivacy`: UserDefaults ist eine „Required Reason API“ (Grund CA92.1), ohne das lehnt Apple ab | S |
| B4 | **Rechtliches:** Datenschutzerklärung-URL, Support-URL, Impressum (Pflicht bei kommerziellem Vertrieb in DE), App-Store-Texte DE/EN | S–M |
| B5 | **Echte Geräte (M0-Spike):** iPhone, Mac-Erinnerungen, geteilte Liste mit zweiter Apple-ID, Einkaufslisten-Typ, Duo (Device Hub oder Gerät) | M |
| B6 | **SwiftData-Versionierung:** `VersionedSchema` und Migrationsplan vor dem ersten Release, sonst werden spätere Modelländerungen riskant (`address`/`detail` kamen schon ohne Schema dazu) | S |
| B7 | **Englisch**, sofern der Launch wie geplant DE+EN ist (0 von 195 Texten übersetzt) | M |
| B8 | **Qualitätsrunde:** VoiceOver-Durchgang, Dynamic Type AX5, Dark Mode, 300-Einträge-Performance, Fehlerzustände (Liste gelöscht, Zugriff entzogen) | M |
| B9 | **TestFlight-Beta** mit mindestens 5 Haushalten, Crash- und Feedback-Auswertung | M (größtenteils Wartezeit) |
| B10 | **Developer-Account und Bundle-ID** festlegen (heute Platzhalter `app.marqet.Marqet`), Markenrecherche „Marqet“ | S |
| B11 | **„Orte“ (E2):** Filialen, Karte, Sortierung nach Entfernung bzw. Smart, Standortfreigabe (Phase 5) | L |

---

## 4. Entscheidungen (getroffen am 26.09.2026)

| # | Frage | Entscheidung | Folgen für den Plan |
|---|---|---|---|
| E1 | Händler-Logos (K1) | **Behalten, Risiko wird getragen** | Rückfall vorbereiten: ein zentraler Schalter `StoreBadge.usesBrandLogos` bzw. eine Build-Einstellung, die auf Monogramme umstellt, damit nach einer Ablehnung innerhalb eines Tages neu eingereicht werden kann. Im Review-Hinweis die beschreibende Nutzung erklären („kennzeichnet den Laden, in dem der Nutzer einkauft“). Den Marken-Hinweis in App und Store-Beschreibung beibehalten. `ASSET_SOURCES.md` für alle 35 Logos vervollständigen |
| E2 | Umfang v1.0 | **„Orte“ in v1.0** | Filialen, Karte, Laden aus der Karte anlegen und Sortierung nach Entfernung bzw. „Smart“ rücken vor den Launch (KONZEPT §14.1, §14.2). Routenplanung (§14.3) bleibt bei v1.3. Neue Launch-Anforderungen: Standortfreigabe „Beim Verwenden“ mit Begründung, MapKit-Spike |
| E3 | Sprachen zum Launch | **Deutsch + Englisch** | Blocker B7 bleibt: 195 Texte plus die neuen Orte-Texte übersetzen, englische Store-Texte und Screenshots |
| E4 | iCloud-Sync der eigenen Läden | **Später** | v1.0 speichert lokal. Abfederung: Läden aus den `🛒`-Markern werden auf jedem Gerät automatisch erkannt (Katalog-Ketten sogar mit Farbe und Logo). Verloren gehen pro Gerät nur eigene Farben und Adressen, Sortierung und Gelerntes. CloudKit-kompatibles Modell beibehalten |
| E5 | Plus-Button und Titel (K2) | offen – **nach dem Duo-Spike** | – |

## 5. Lücken zum vollen Wunschzustand nach Version

| Version | Inhalt | Status | Grundlage im Code |
|---|---|---|---|
| **v1.0** | wie oben plus iPad-Kurzbefehle, Zeiger-Effekte, mehrere Fenster, Items per Drag sortieren, Kategorie per Drag, Wörterbuch ≈ 2.500 Begriffe | 🟡 | – |
| **v1.1 „Schneller“** | Siri und Kurzbefehle (App Intents), interaktive Widgets, Prospekt-Link, `@Laden`-Syntax, Hinweis „Meist bei Rewe“, Katalog-Updates vom Server, Duo-Küchenmodus, linke Seite anheften, Text aus anderen Apps auf eine Card ziehen | ❌ | Katalog-Felder `leafletURL` vorbereitet, `onHingeChange` im SDK |
| **v1.0 (vorgezogen, E2): „Orte“** | Filialen per MapKit, Karte, Laden aus der Karte anlegen, Sortierung nach Entfernung und „Smart“ | ❌ | `address` als Freitext vorhanden, `mapSearchTerms` im Katalog, Spezifikation in KONZEPT §14 |
| **v1.3 „Unterwegs“** | Einkaufsrunde mit Routenoptimierung, Standort-Hinweise, Apple Watch, Live Activity | ❌ | Spezifikation in KONZEPT §14.3 |
| **v2.0 „Angebote“** | Angebote passend zur Liste über einen Partner (ShopFully oder Bonial) | ❌ | Geschäftsthema, Gates G1–G4 in der MARKTANALYSE |

---

## 6. Plan

Die Reihenfolge folgt dem kritischen Pfad zum Launch. Alles, was nicht auf ihm liegt, läuft parallel oder danach.

### Phase 0 · Stabilisieren und entscheiden (sofort)
1. **Entscheidungen E1–E4** treffen (§4).
2. **Eine Quelle für die Projektdatei** festlegen (K4) und den Stand sauber auf `main` bringen, inklusive der offenen Änderungen (heute 9 Dateien in Arbeit). Die 4 fehlschlagenden `AppModelTests` an die immer sichtbare Unsortiert-Card anpassen.
3. **CI einrichten** (GitHub Actions oder Xcode Cloud): `swift test` plus `xcodebuild test` auf dem Simulator bei jedem Push. Feature-Branches für parallele Arbeit.
4. **Doku nachziehen:** Konzept an K3 und die neuen Funktionen anpassen (Rückgängig, Adresse, Akzentfarben).

**Fertig, wenn:** der Build auf `main` sauber ist, die CI grün ist und die Entscheidungen dokumentiert sind.

### Phase 1 · Realitätscheck auf echter Hardware (M0, überfällig)
- iPhone mit iCloud: Marker-Sync zum Mac, geteilte Liste mit zweiter Apple-ID (einmal ohne Marqet), Siri-Eingabe bei offener App, Liste vom Typ „Einkaufen“.
- iPhone Duo: Anker-Seite, Falz-Region, senkrechte Leiste mit eigenem Plus (K2), Sheets links, Drag über den Falz, Tastatur beim Falten.
- Foundation Models: 50 echte deutsche Einträge, Treffsicherheit und Latenz messen, Schwellen anpassen.
- Kategorisierung: Goldset um echte Listen aus deinem Haushalt erweitern.

**Fertig, wenn:** alle Spike-Fragen mit Ja oder Nein beantwortet sind und die Befunde als Aufgaben erfasst sind.

### Phase 2 · Kauf (M7)
- StoreKit 2: Einmalkauf `…pro` mit Familienfreigabe, `Transaction.updates`-Listener, Offline-Cache.
- Paywall-View, Auslöser an den gesperrten Pro-Schaltern und am Ende des Zuordnens, „Käufe wiederherstellen“.
- StoreKit-Testkonfiguration und Tests: Kauf, Rückerstattung, Familienfreigabe.

**Fertig, wenn:** Kauf und Wiederherstellen in der Sandbox funktionieren und der Debug-Schalter nur noch in Debug-Builds existiert.

### Phase 3 · Launch-Reife (M8), parallel zu Phase 4 und 5
- Blocker B2–B4, B6–B8 abarbeiten: Logo-Rückfallschalter und Quellen-Doku (E1), Datenschutz-Manifest, Rechtliches, SwiftData-Versionierung **inklusive `StoreLocation`**, Englisch, Qualitätsrunde.
- Standort: `NSLocationWhenInUseUsageDescription` (DE/EN). Datenschutz-Angaben prüfen: MapKit-Anfragen gehen an Apple, nicht an uns, das Label bleibt voraussichtlich „Keine Daten erfasst“.
- App-Store-Material: Screenshots über `-demo` auf iPhone, iPad und Duo, Texte, Datenschutz-Angaben („Keine Daten erfasst“).
- TestFlight-Beta (B9): 2–3 Wochen, danach Fixes.

**Fertig, wenn:** die TestFlight-Build keine Crash-Cluster zeigt, die Beta-Rückmeldungen eingearbeitet sind und die App eingereicht ist.

### Phase 4 · Restliche v1.0-Lücken (parallel zu Phase 3)
- iPad: Kurzbefehle (⌘N, ⌘←/→, ⌘1–9, Leertaste, ⌘⌫), Zeiger-Effekte, mehrere Fenster (Status pro Szene prüfen).
- Items innerhalb eines Abschnitts per Drag sortieren (Free), Kategorie per Drag zwischen Abschnitten ändern.
- Duo-Befunde aus Phase 1 umsetzen.
- Wörterbuch mit Beta-Daten auf ≈ 2.500 Begriffe ausbauen.

### Phase 5 · „Orte“ für v1.0 (E2)
1. **MapKit-Spike** (Teil von Phase 1): Finden `MKLocalSearch` und `MKLocalPointsOfInterestRequest` die Filialen der Katalog-Ketten in DE, AT und CH zuverlässig? Wie trifft die Ketten-Erkennung über `mapSearchTerms`? Wie verhält sich MapKit beim Rate-Limit?
2. **Datenmodell:** `StoreLocation` (Filiale, `MKMapItem.identifier`, Koordinate, bevorzugt ja/nein). Das heutige Freitext-Feld `address` wird bei der Filialwahl befüllt bzw. in eine Filiale migriert. Das kommt in die erste `VersionedSchema` (B6).
3. **Filialen finden und wählen:** pro Laden „Filiale wählen“ (Suche plus Karte), automatische Vorschläge in der Nähe, bevorzugte Filiale.
4. **Karte:** Toolbar-Item „Karte“, Pins in Laden-Farbe mit Anzahl offener Einträge, blasse Pins für Katalog-Ketten in der Nähe („hinzufügen?“). Auf iPad und Duo liegt die Karte links, die aktive Card rechts.
5. **Laden aus der Karte anlegen:** POI wählen, Kette erkennen, sonst eigenen Laden anlegen.
6. **Sortierung der Läden:** Manuell (Standard), Entfernung, Smart `Artikel / (Anfahrt + 5 min)`, mit ETA-Cache. Neu sortiert wird nur beim Öffnen, nie unter dem Finger.
7. **Standort optional:** Ohne Freigabe funktioniert alles wie heute.
8. **Tests:** Unit-Tests für Sortierung und Ketten-Erkennung, UI-Durchgang mit und ohne Standortfreigabe.

**Fertig, wenn:** auf einem echten Gerät in deiner Umgebung Filialen gefunden werden, die Smart-Sortierung plausibel ist und alles ohne Standortfreigabe weiter funktioniert.

### Phase 6 · Launch v1.0

### Phase 7 · v1.1 „Schneller“ (erstes Update nach dem Launch)
App Intents und Siri, Widgets, Prospekt-Link, `@Laden`-Syntax, Hinweis „Meist bei Rewe“, Katalog-Updates vom Server, Duo-Küchenmodus, linke Seite anheften, Text aus anderen Apps auf eine Card ziehen, **iCloud-Sync der eigenen Läden (E4)**.

### Phase 8 · v1.3 „Unterwegs“
Einkaufsrunde mit Routenoptimierung (Tiefkühlware zuletzt), Übergabe an Apple Maps, Standort-Hinweise, Apple Watch, Live Activity. Baut direkt auf den Filialen aus Phase 5 auf.

### Phase 9 · v2.0 „Angebote“ (Geschäftsthema)
Nach dem Launch das Erstgespräch mit ShopFully bzw. Bonial führen. Mit Vertrag dann Angebots-Treffer (per Opt-in über PLZ). Bei der Gelegenheit die Logo-Rechte (E1) mit den Händlern absichern.

---

## 7. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Ablehnung durch App Review oder Abmahnung wegen Markenlogos (Risiko bewusst getragen, E1) | Rückfallschalter auf Monogramme, beschreibende Nutzung im Review-Hinweis, Marken-Hinweis, vollständige Quellen-Doku; Logo-Rechte über die Partnerschaft v2.0 absichern |
| „Orte“ verlängert den Weg zum Launch (E2) | MapKit-Spike früh in Phase 1; Routen bleiben konsequent bei v1.3 |
| iPad bzw. zweites iPhone ohne eigene Läden und Gelerntes (E4) | Auto-Erkennung über die Marker; iCloud-Sync in v1.1 |
| Duo-Verhalten weicht von der Annahme ab (Anker-Seite, senkrechte Leiste) | Phase 1 vor weiteren Duo-Features |
| Marker kollidiert mit Sync oder mit Bearbeitungen in Erinnerungen | Phase 1 mit geteilter Liste und Mac |
| Foundation Models zu langsam oder ungenau auf Deutsch | Messung in Phase 1, Ladenart-Heuristik als Fallback ist vorhanden |
| Parallele Änderungen brechen den Build (ist heute passiert: veralteter Cache, Projektdatei) | CI und Branches (Phase 0) |
| Umfang wächst weiter vor dem Launch | Nach „Orte“ ist der Umfang für v1.0 eingefroren; Routen, Siri und Angebote kommen danach |

---

## 8. Nächste Schritte

1. Phase 0: laufende Änderungen committen, die 4 App-Tests reparieren, eine Quelle für die Projektdatei, CI, Doku (Konzept an E1–E4 und K3 anpassen).
2. Phase 1: Testprotokoll für iPhone, Mac, geteilte Liste und Duo, dazu der MapKit-Spike.
3. Phase 2 (StoreKit) starten, danach Phase 5 („Orte“).
