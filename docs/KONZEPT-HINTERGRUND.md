# Preise und Inbox im Hintergrund

Stand: 28.09.2026 · Status: **Konzept**, Stufe 1 umgesetzt · Ergänzt [OFFENE-DATEN.md](OFFENE-DATEN.md)

**Frage:** Wann lädt Marqet Preise, ohne den Nutzer zu stören und ohne die App langsamer zu machen? Und kann Marqet im Hintergrund merken, dass neue Einträge in der Erinnerungsliste auf einen Laden warten?

**Kurzantwort:**

- Preise ändern sich langsam: Open Prices sammelt Beobachtungen über Wochen, und Marqet zeigt Einstiegspreise, keine Tagesangebote. **Einmal am Tag reicht.** Häufiger laden bringt keine besseren Daten, nur mehr Anfragen.
- **Nie auf dem Startpfad.** Der erste Frame der Liste darf nie auf das Netz warten.
- Empfohlen sind drei Zeitpunkte, alle leise: **Onboarding** (umgesetzt), **beim Öffnen gedrosselt** (nur Fälliges) und ein **täglicher Hintergrundauftrag**. Dieser Auftrag prüft auch die Inbox und kann optional eine Mitteilung schicken.

---

## 1. Zeitpunkte für den Preisabruf

| Zeitpunkt | Was | Belastung | Status |
|---|---|---|---|
| **Onboarding** | 18 Grundartikel (Milch, Butter, Brot …) landesweit, während der Nutzer die Willkommensseiten liest. Ohne Standortfrage | ~20–60 s Netz im Hintergrund, abseits des Main Actors. Das Onboarding dauert länger | ✅ `prefetchStaplePrices()` |
| **Bei Bedarf** | Kategorien der gerade sichtbaren Einträge, beim Öffnen von Zuordnen, Laden-Card oder Angeboten | Nur fällige Kategorien (älter als 24 h) | ✅ bestehend |
| **Beim Öffnen der App** | Fällige Kategorien der offenen Liste nachladen. **Erst 2 s nach dem ersten Frame**, Priorität `.utility`, **höchstens 6 Kategorien** pro Öffnen | Unmerklich, weil nichts auf dem Startpfad liegt und die Menge begrenzt ist | 🟡 Stufe 2 |
| **Täglich im Hintergrund** | `BGAppRefreshTask`, frühestens ab 6 Uhr: Kategorien der offenen Liste plus Grundartikel, **so viele, wie in ~25 s passen** | Das System wählt den Zeitpunkt nach dem Nutzungsmuster (meist kurz vor dem üblichen Öffnen) und bricht nach ~30 s ab. Der Cache speichert nach jeder Kategorie, ein Abbruch verliert also nichts | 🟡 Stufe 3 |

**Nicht empfohlen:**

- **Abruf bei jedem Öffnen ohne Drossel.** Das kostet Akku und Anfragen, ohne dass die Daten besser werden.
- **`BGProcessingTask` nachts.** Er ist für Minuten-Arbeiten gedacht und läuft oft nur am Ladegerät. Für Preise ist das zu schwer und zu unzuverlässig.
- **Push vom Server.** Marqet hat keinen Server, und der Ansatz „kein Konto“ bleibt.

**Standort im Hintergrund:** Der Hintergrundauftrag fragt nie nach einer neuen Position. Er nutzt das zuletzt gerundete Gebiet oder, ohne Freigabe, das Land. Den Datenschutztext muss das nicht ändern.

---

## 2. Guardrails: lieber kein Preis als ein falscher

Umgesetzt in `PriceFreshness` (MarqetCore, getestet). Jede Stelle, die Geld zeigt, läuft darüber: Zuordnen, Laden-Card, Übersicht, Angebote, Vorschläge.

| Regel | Wert | Wirkung |
|---|---|---|
| Neu laden ab | 24 h nach dem letzten Erfolg | Vorher keine Anfrage |
| **Keine Geldwerte mehr** | **7 Tage ohne erfolgreiche Aktualisierung** | Preise, Richtwerte und der Preis-Vorschlag verschwinden. Die Liste funktioniert unverändert weiter |
| Preisfunde (Angebote) | 2 Tage | Sie sind wochenaktuell gemeint und verfallen deshalb schneller |
| Alte Beobachtungen | älter als 60 Tage | Die Kette fällt aus dem Vergleich, auch nach einem frischen Abruf |
| Nach einem Fehler | 1 h Pause pro Kategorie | Kein Dauerfeuer bei Funkloch oder Serverstörung |
| Rückfall | lokales Gebiet → Land | Die Preise aus dem Onboarding wirken weiter, auch wenn später der Standort freigegeben wird |

*Offen (Stufe 2):* In den Einstellungen unter „Letzte Preisabfrage“ ein Hinweis, wenn die Preise ausgeblendet sind („Preise werden ausgeblendet, bis eine Aktualisierung gelingt“).

---

## 3. Neue Einträge in der Erinnerungsliste

**Ausgangslage:** EventKit meldet Änderungen (`EKEventStoreChanged`) nur, solange Marqet läuft. Einen Push für neue Erinnerungen gibt es nicht. Der tägliche Hintergrundauftrag darf die Erinnerungen aber lesen, der Vollzugriff besteht ja schon.

**Ablauf im täglichen Auftrag (derselbe `BGAppRefreshTask` wie oben):**

1. Liste laden, Marker auswerten und **Pro-Automatik zuerst** zuordnen lassen. Mitteilungen gibt es nur für den Rest.
2. Unsortierte Einträge mit dem zuletzt gemeldeten Stand vergleichen (IDs im App-Group-Speicher).
3. Gibt es **neue** unsortierte Einträge, folgen die Signale unten, vom leisesten zum lautesten.

| Signal | Wirkung | Voraussetzung | Empfehlung |
|---|---|---|---|
| **Widget** aktualisieren | „3 zum Zuordnen“ auf dem Homescreen | nichts Neues, die Widgets gibt es schon | ✅ immer |
| **App-Symbol-Badge** mit der Anzahl | still, sichtbar beim nächsten Blick | Mitteilungs-Erlaubnis (Badge) | ✅ Standard, wenn erlaubt |
| **Mitteilung** „Neu auf deiner Liste: Milch, Batterien, Geschenkpapier – Läden zuordnen?“, Tipp öffnet `marqet://triage` | aktiv, kann stören | Erlaubnis plus eigener Schalter „Hinweis bei neuen Einträgen“ | 🟡 **Opt-in**, höchstens 1× pro Tag, nicht zwischen 21 und 8 Uhr, nie zweimal für dieselben Einträge |
| **Bei Ankunft im Laden** (bestehende Ankunftsmeldung) | „Bei Rewe: 4 Einträge · 2 weitere ohne Laden“ | Ankunftsmeldungen an | ✅ kleine Erweiterung, passt in den Moment |

**Wann nach der Erlaubnis fragen:** nicht im Onboarding. Die Frage kommt nach dem ersten erfolgreichen Zuordnen, mit dem konkreten Nutzen: „Soll Marqet dir Bescheid geben, wenn neue Einträge dazukommen?“

**Grenzen, die man kennen muss:**

- iOS entscheidet, **ob und wann** der Hintergrundauftrag läuft. Wer Marqet selten öffnet, bekommt ihn selten. Wer die App aus dem App-Umschalter wischt, bekommt ihn gar nicht mehr. Eine Mitteilung „genau dann, wenn der Partner etwas einträgt“ ist damit **nicht möglich**, gemeint ist eher „morgens eine Zusammenfassung“.
- Der Auftrag hat ~30 s. Reihenfolge: zuerst die Inbox (schnell, lokal), dann die Preise.

---

## 4. Stufen

| Stufe | Inhalt | Aufwand |
|---|---|---|
| **1** ✅ | Preise im Onboarding, Guardrails (`PriceFreshness`), Rückfall auf das Land | erledigt |
| **2** | Drosselung beim Öffnen (2 s Verzögerung, ≤ 6 fällige Kategorien); Hinweis in den Einstellungen, wenn Preise ausgeblendet sind | klein |
| **3** | `BGAppRefreshTask` (Info.plist: `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes: fetch`), Inbox-Abgleich, Widget und Badge | mittel |
| **4** | Opt-in-Mitteilung für neue Einträge, Erweiterung der Ankunftsmeldung | klein bis mittel |

**Offene Entscheidungen:**

- Badge standardmäßig an (empfohlen), sobald die Mitteilungs-Erlaubnis besteht?
- Uhrzeit der Morgen-Zusammenfassung: fest (z. B. 7:30) oder dem System überlassen (empfohlen, weil zuverlässiger)?
- Sollen Mitteilungen auch Einträge nennen, die ein Familienmitglied hinzugefügt hat („Anna: Milch“)? EventKit liefert den Ersteller nicht zuverlässig. Empfehlung: keine Namen.
