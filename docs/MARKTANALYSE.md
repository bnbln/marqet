# Marqet – Wettbewerb, Angebote & Langfrist-Strategie

Stand: 26.09.2026 · Ergänzt [KONZEPT.md](KONZEPT.md)

---

## 1. Wettbewerbsanalyse

| App | Modell | Stärken | Schwächen | Was Marqet daraus mitnimmt |
|---|---|---|---|---|
| **Bring!** | Kostenlos, finanziert über Partner (Angebote, Rezepte, Marken) | Artikel-Katalog mit Icons, automatische Kategorie-Sortierung, geteilte Listen, Rezepte, **Prospekte & Angebote direkt auf die Liste**, Kundenkarten | Eigenes Datensilo, keine Laden-Ansicht (nur über mehrere Listen), viel Partner-Content | Kategorie-Qualität als Messlatte; der Weg „Angebot → Liste“ ist das Vorbild für v2 |
| **MeinProspekt** (Bonial / Axel Springer, Schwester von kaufDA) | Werbefinanziert (Händler zahlen für Reichweite) | Prospekte von tausenden Händlern, „+ Merken“ legt ein Angebot auf die Liste, geteilte Listen, Favoriten-Alarme | Die Liste ist Beiwerk zum Prospekt, keine echte Einkaufsplanung | Angebote werden pro Produkt gemerkt; Favoriten-Alarm als spätere Idee |
| **Listonic** (DE: „Die Einkaufsliste – Listonic“) | Kostenlos, Werbung + Offerista-Placements | Sortierung nach Gängen, Kategorien-Reihenfolge anpassbar, Preise/Budget, Echtzeit-Sharing | Werbelastig, generisches Design | Anpassbare Kategorie-Reihenfolge pro Laden ist Standard und muss rein |
| **Die Einkaufsliste** (unabhängige App) | Kostenlos | Mengen/Einheiten-Erkennung, **Kategorie-Reihenfolge pro Supermarkt** konfigurierbar | Alles manuell, eigenes Silo | Bestätigt die Idee „Laufweg pro Laden“; Marqet lernt ihn automatisch statt per Konfiguration |
| **Apple Erinnerungen** | Systemapp | **Beste Kategorisierung** (Listentyp „Einkaufen“, 12 Kategorien, lernt aus manuellen Korrekturen, mehrsprachig mit Apple Intelligence), Siri, Watch, Mac, Familienfreigabe | Kein Laden-Konzept, keine Laufweg-Sortierung | Kategorien sind **nicht über EventKit lesbar** (auch im SDK von iOS/macOS 27 nicht), deshalb baut Marqet eine eigene Kategorisierung in Apple-Qualität |
| **Todoist** | Freemium-Abo | Schnelle Eingabe, Labels, Filter, Sharing | Kein Einkaufsbezug. Nutzer bauen sich Laden-Labels („@aldi“) selbst | Bestätigt den Marker-Ansatz: Menschen ordnen Läden schon heute manuell über Labels zu |
| **Things 3** | Einmalkauf pro Plattform | Referenz für Design und Gesten, übernimmt Erinnerungen in den Eingang | **Kein Teilen**, nicht für Einkäufe gemacht | Polish-Niveau als Maßstab; „Erinnerungen als Eingangskanal“ ist bewährt |
| **TickTick** | Freemium-Abo | Sharing, Abschnitte, **standortbasierte Erinnerungen** | Generisch und überladen | Standort-Hinweis „Du bist bei Aldi“ als spätere Idee (v1.3) |

### Die Lücke

Keine App ist gleichzeitig **nach Läden organisiert** und **nativ in Apple Erinnerungen**:
- Bring! und Listonic sortieren nach *Kategorie*, halten die Daten aber im eigenen Silo.
- Apple kategorisiert hervorragend, kennt aber keine *Läden*.
- Todoist, TickTick und Things sind generische To-do-Apps.

**Positionierung:** *„Deine Einkaufsliste aus Erinnerungen – nach Läden sortiert, im Laufweg deines Markts.“*

| Vorteil | Bewusst in Kauf genommen |
|---|---|
| Kein Lock-in: Löscht man die App, bleibt alles in Erinnerungen | Nur iOS (kein Android-Partner im Haushalt) |
| Siri, Watch, Mac, CarPlay und Familienfreigabe bringt Apple mit | Keine Rezepte |
| Zuordnen-Flow und Laufweg-Lernen pro Laden | Angebote erst ab v2 (siehe unten) |
| Privatsphäre: keine Konten, keine Werbung, KI auf dem Gerät | – |

---

## 2. Angebote: Gibt es eine API?

**Kurz: In DACH gibt es keine öffentliche, frei nutzbare Angebots-API.** Die Daten liegen bei zwei Vermarktern, die sie gezielt an Partner-Apps ausspielen.

| Quelle | Daten | Zugang | Rechtslage | Bewertung |
|---|---|---|---|---|
| **ShopFully** (früher Offerista Group: marktjagd, handelsangebote.de) | Prospekte + Einzelangebote, lokal nach Standort | **Publisher-Partnerschaft**: Integration per Code-Snippet/API, Abrechnung pro Klick (Prospekt geöffnet). Beliefert laut eigenen Angaben 160+ Publisher, u. a. Bring!, Listonic, Chefkoch, Payback, Bing | Vertraglich sauber | ⭐ **Realistischster Weg.** Reichweite ist die Eintrittskarte |
| **Bonial** (kaufDA, MeinProspekt; Axel Springer) | Marktführer bei Prospekten, rund 1.500 Händler; „Bonial Reach“ spielt Angebote auf externen Plattformen aus | Partnerschaft auf Anfrage (B2B) | Vertraglich sauber | ⭐ Zweite Option, eher auf große Reichweiten ausgerichtet |
| **Publitas** | Digitale Prospekte, die Händler selbst hochladen, mit Entwickler-API | Pro Händler, der Publitas nutzt | Mit Zustimmung des Händlers ok | Skaliert nicht für den Start |
| **marktguru** | Angebote nach PLZ und Suchbegriff | Nur **inoffiziell** (API-Keys werden aus der Website ausgelesen) | Verstößt gegen die AGB, Risiko nach § 87b UrhG (Datenbankherstellerrecht) und UWG, App-Review-Risiko | ❌ No-Go |
| **Händler-APIs** (REWE, Lidl Plus, Edeka) | Angebote und teils Preise | Nur private, reverse-engineerte Schnittstellen | wie oben | ❌ No-Go |
| **Scraping** (z. B. Apify-Actors für kaufDA) | Prospekte | – | wie oben | ❌ No-Go |

### Nachrecherche 26.09.2026

| Quelle | Befund | Folgerung |
|---|---|---|
| **Open Prices** (Open Food Facts, [API](https://prices.openfoodfacts.org/api/docs), ODbL) | Einzige **offene, legale** Preisdatenbank. Crowdsourcing per Kassenbon/Preisschild. In Deutschland aktuell nur rund **1.070 Orte**, die aktivsten mit wenigen hundert Preisen (z. B. Netto Strausberg 1.150, EDEKA München 597, Rewe Bielefeld 264) | Für Angebote ungeeignet (keine Aktionen, keine Aktualität). Später denkbar als Hinweis „zuletzt gesehen: 1,19 € bei Lidl“ mit Quellenangabe, oder Marqet-Nutzer tragen selbst bei |
| **kaufDA / Bonial** | Hat 2025 eine **eigene Einkaufsliste mit integrierten Angeboten** gestartet ([retail-news](https://retail-news.de/kaufda-einkaufsliste-launch-2025/)) | Bonial ist damit direkter Wettbewerber, als Datenpartner unwahrscheinlicher |
| **ShopFully** | Publisher-Programm mit 1.400+ Publishern ([Solutions for Publishers](https://shopfully.com/business-solutions/publishers/)) | Bleibt der **realistischste Partner** für Einzelangebote (v2.0) |
| **Offizielle Händlerseiten** | Jede große Kette hat eine öffentliche Angebots- bzw. Prospektseite, teils mit Marktwahl | Ab v1.0 als Link im Laden-Vollbild (KONZEPT #39), `leafletURL` im Katalog (25 Ketten) |
| Staatliche Preisbeobachtung | In Deutschland nur gefordert (vzbv, foodwatch), keine offenen Daten; Österreich hat einen Preistransparenz-Bericht der AMA, aber keine Einzelpreise | Keine Quelle |

**Wichtige Einschränkung beim „besten Angebot“:** Verfügbar sind nur **Aktionspreise** aus Prospekten, **keine regulären Preise**. Ein echter Warenkorb-Preisvergleich („bei Lidl insgesamt 4,20 € billiger“) ist damit nicht seriös möglich. Möglich ist: *„Butter ist diese Woche bei Lidl im Angebot (1,69 €, bis Sa)“*. Genau so müssen wir das Feature auch vermarkten.

---

## 3. Zielbild Angebote (ab v2.0)

### 3.1 Features in Stufen

| Stufe | Feature | Nutzen |
|---|---|---|
| **v1.0 – Prospekt-Link** ✅ | Im Laden-Vollbild öffnet „Aktueller Prospekt“ die offizielle Angebotsseite des Händlers (`SFSafariViewController`, `leafletURL` aus dem Katalog) | Ohne Partner, ohne Daten, rechtlich unkritisch |
| **v1.x – Prospekt pro Markt** | Filial-ID der bevorzugten Filiale in die URL (z. B. Rewe-Marktseite), damit der Nutzer nicht erneut seinen Markt wählen muss | Braucht je Kette ein URL-Schema, nur für die großen 5 |
| **v2.0 – Angebots-Treffer** | Für jedes offene Item wird geprüft, ob es in einem der Läden des Nutzers im Angebot ist. Das Item bekommt ein Badge `🏷 Lidl 1,69 € · bis Sa`, im Zuordnen-Screen erscheint „Im Angebot bei Lidl“ als Vorschlagsgrund, jede Laden-Card bekommt ein Sheet „Angebote für deine Liste“ | Der eigentliche Wow-Effekt: das beste Angebot wird zur Liste passend vorgeschlagen |
| **v2.0 – Angebot → Liste** | Angebote eines Ladens durchsuchen, per Tipp mit Marker direkt auf die Liste | Wie bei Bring! und MeinProspekt |
| **v2.x – Einkauf optimieren** | Kombiniert Angebote, Entfernung und Artikelmenge: „Wenn du Butter und Kaffee bei Lidl statt Aldi kaufst, sparst du ca. 3,10 € bei 4 min Umweg“ | Verbindet sich mit der Routenplanung (v1.3) |

### 3.2 Technik (Skizze)

- `OfferProvider`-Protokoll mit einer Implementierung pro Partner. Der Katalog-`key` jedes Ladens wird auf die Händler-ID des Partners gemappt.
- **Matching Item ↔ Angebot:** normalisierter `itemKey`, dann Kategorie-Abgleich, dann semantischer Vergleich („Milch“ ↔ „Weihenstephan H-Milch 1,5 % 1 l“) über `NLEmbedding` oder Foundation Models. **Hohe Schwelle:** Ein falscher Treffer kostet mehr Vertrauen, als ein fehlender Treffer nützt.
- Angebote **ordnen nie automatisch zu**, sie sind immer nur ein Hinweis.
- Cache pro Prospektwoche und PLZ, Aktualisierung höchstens einmal täglich im Hintergrund (`BGAppRefreshTask`).

### 3.3 Datenschutz & Recht

- **Opt-in:** „Angebote aktivieren“ fragt nach der PLZ (nicht nach dem genauen Standort). Ohne Opt-in bleibt Marqet bei „Keine Daten erfasst“.
- Mit Opt-in ändert sich das Privacy-Label (PLZ bzw. grober Standort geht an den Partner, *nicht mit der Person verknüpft*). Kein Tracking, keine Werbe-ID, kein ATT-Dialog.
- **Bezahlte Platzierungen müssen als „Anzeige“ gekennzeichnet werden** (UWG, DSA). Organische Treffer aus dem eigenen Matching sind keine Anzeige, gesponserte Hervorhebungen schon.
- Keine Logos ohne Lizenz, auch nicht in Angebotskarten (der Partner liefert gegebenenfalls lizenzierte Bilder mit).

### 3.4 Geschäftsmodell

- Pro-Einmalkauf bleibt bestehen. Angebote sind **für alle kostenlos**, weil sie Reichweite bringen und der Partner pro Klick vergütet.
- Beide Erlösquellen passen zusammen: Pro verkauft Zeitersparnis, Angebote bringen Geldersparnis.

---

## 4. Strategische Bewertung & Entscheidungs-Gates

**Warum nicht in v1:**
1. Ohne Reichweite gibt es keinen Partnervertrag. Der Zugang zu den Daten ist ein Geschäftsdeal, kein technisches Problem.
2. Angebote ändern das Privacy-Profil und die Positionierung. Das muss sich bewusst auf ein funktionierendes Kernprodukt draufsetzen.
3. Das MVP muss zuerst den Kern validieren: Zuordnen und Laufweg.

**Gates für v2.0 Angebote:**

| Gate | Kriterium |
|---|---|
| G1 Produkt | Retention nach 4 Wochen stabil, Nutzer ordnen regelmäßig Items zu |
| G2 Reichweite | Konkrete Nutzerzahlen als Verhandlungsbasis, erstes Gespräch mit ShopFully (Publisher) und Bonial (Reach). Mindestschwellen und Konditionen werden dort geklärt |
| G3 Vertrag | Datenumfang (Einzelangebote, nicht nur Prospekt-PDFs), Regionen DE/AT/CH, Vergütung, Kennzeichnungspflichten |
| G4 Datenschutz | Opt-in-Konzept, Datenschutzerklärung, Privacy-Label aktualisiert |

**Vorbereitung schon in v1 (ohne Mehraufwand):**
- Stabile Katalog-`key`s für alle Ketten (später Mapping auf Partner-IDs).
- Kategorien und normalisierte `itemKey`s, die das Angebots-Matching später braucht.
- Datenmodell mit Filialen (`StoreLocation`) vorbereitet, die UI dafür kommt in v1.2.

---

## Quellen

- [Bring! – Features](https://getbring.com/de/features) · [appgefahren: Bring! integriert Angebote und Prospekte](https://www.appgefahren.de/bring-einkaufsliste-integriert-angebote-und-prospekte-217824.html) · [mobiflip: Vom Prospekt direkt auf die Einkaufsliste](https://www.mobiflip.de/bring-vom-prospekt-direkt-auf-die-einkaufsliste/)
- [Offerista kooperiert mit Listonic](https://www.offerista.com/pm-offerista-kooperiert-internationaler-einkauflisten-app-listonic/) · [Offerista for Publishers](https://www.offerista.com/en/offerista-for-publishers/) · [Offerista & Publitas Kooperation](https://www.offerista.com/de/die-zukunft-des-prospekts-offerista-und-publitas-starten-europaweite-kooperation/) · [Shopfully & Offerista: neue Marke](https://shopfully.com/newsroom/shopfully-offerista-new-brand-identity/)
- [Bonial – Unternehmen](https://www.bonial.com/en/company) · [Bonial Reach](https://www.bonial.com/produkte-bonial-reach) · [Supermarkt Inside: Wer ist kaufDA/MeinProspekt?](https://www.supermarkt-inside.de/wer-und-was-ist-kaufda-meinprospekt/)
- [MeinProspekt – App Store](https://apps.apple.com/de/app/meinprospekt-mit-einkaufsliste/id1031838771) · [MeinProspekt Support: Angebot auf die Einkaufsliste](https://support.meinprospekt.de/hc/de/articles/10450115270290-Wie-kann-ich-ein-Angebot-zu-meiner-Einkaufsliste-hinzuf%C3%BCgen)
- [marktguru inoffizielle API (GitHub)](https://github.com/Nusscookie/offers-api) · [kaufDA-Scraper (Apify)](https://apify.com/bovi/kaufda-circulars)
- [Listonic](https://listonic.com/) · [Die Einkaufsliste – App Store](https://apps.apple.com/de/app/die-einkaufsliste/id1082845559)
- [Apple Support: Einkaufsliste in Erinnerungen](https://support.apple.com/guide/iphone/make-a-grocery-list-iph80ba26e1f/ios) · [EventKit ohne Sections/Tags im 27er-SDK (GitHub-Issue)](https://github.com/oliverames/apple-core/issues/40)
- [TickTick vs. Things 3 (TechRepublic)](https://www.techrepublic.com/article/ticktick-vs-things-3/) · [Todoist vs Things 3 vs TickTick](https://blog.rivva.app/p/todoist-vs-things-vs-ticktick)
- [Apple Map Links](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html) · [Apple Maps Multi-Stop (Cult of Mac)](https://www.cultofmac.com/how-to/apple-maps-multiple-stops)
