# Preisdaten: Welche kostenlosen Quellen gibt es?

Stand: 26.09.2026 · Ergänzt [MARKTANALYSE.md](MARKTANALYSE.md), Abschnitt 2 (Angebote-APIs)

**Frage:** Kommen wir kostenlos an Lebensmittelpreise, sodass Marqet „einen gewissen Stand“ an Preisen zeigen kann? Oder ist das zu viel?

**Kurzantwort:**

- Einen **vollständigen, aktuellen Preisvergleich** über alle Märkte bekommen wir weder kostenlos noch legal. In Deutschland gibt es keine offene Preisdatenbank, keine Meldepflicht und keine offizielle API. Wer so etwas anbietet, scrapt entweder (Preisrunter, heisse-preise) oder sammelt Kassenbons in großer Menge (Smhaggle, SupermarktCheck).
- **Einen „gewissen Stand“ bekommen wir aber, und zwar sauber.** Die drei tragfähigen Bausteine sind:
  1. Preise, die der Nutzer selbst erfasst (Kassenbon oder Preisschild, auf dem Gerät erkannt)
  2. kuratierte Richtpreise für rund 300 Basisartikel
  3. Open Prices als offene Zusatzquelle (dünn, aber legal)
- Aktionspreise pro Woche kommen weiterhin nur über einen Partner (ShopFully/Bonial). Bis dahin bleibt es beim Prospekt-Link aus v1.0.

---

## 1. Welche Arten von Preisdaten gibt es?

Die Quellen liefern sehr unterschiedliche Daten. Deshalb zuerst eine Einordnung:

| Art | Beispiel | Wofür in Marqet |
|---|---|---|
| **Aktionspreis** (Prospekt) | „Butter 1,69 €, Mo–Sa bei Lidl“ | Angebot → Liste (v2.0) |
| **Regalpreis** (regulär, pro Kette, teils pro Markt) | „Butter 250 g bei REWE Musterstraße: 2,29 €“ | Echter Preisvergleich, Warenkorb-Summe |
| **Eigener Preis** (vom Nutzer bezahlt) | „Zuletzt bezahlt: 2,19 € bei Edeka, 12.09.“ | Preisgedächtnis, Budget, Verlauf |
| **Richtpreis** (Spanne, nicht marktgenau) | „Butter 250 g: ca. 1,79–2,49 €“ | Grobe Einkaufssumme vor dem Einkauf |
| **Index / Statistik** | „Nahrungsmittel +2,1 % zum Vorjahr“ | Kontext, kein Produktpreis |

---

## 2. Alle Quellen im Überblick

Legende: ✅ kostenlos und legal · 🟡 kostenlos mit Auflagen oder Aufwand · 🟠 Grauzone · ❌ No-Go bzw. nicht kostenlos

### 2.1 Offene Daten

| Quelle | Daten | Umfang in Deutschland | Zugang & Lizenz | Bewertung |
|---|---|---|---|---|
| **Open Prices** (Open Food Facts) | Regalpreise per EAN, aus Kassenbons und Preisschild-Fotos | Siehe 2.2. **Rund 8.200 Preise in den letzten 12 Monaten**, verteilt auf ~520 Märkte | REST-API ([Doku](https://prices.openfoodfacts.org/api/docs)) und täglicher Parquet-Dump ([Hugging Face](https://huggingface.co/datasets/openfoodfacts/open-prices)), **ODbL** | ✅ Einzige offene Preisquelle. Zu dünn als Vergleich, aber gut als Hinweis. Wir können beitragen |
| **Open Food Facts** Produktdatenbank | Name, Marke, Menge, Kategorie, Bild pro EAN, **keine Preise** | Sehr gut, ~4,4 Mio. Produkte weltweit | API und Dump, ODbL | ✅ Nützlich, um EAN aus Kassenbon oder Preisschild einem Artikel zuzuordnen |
| **Destatis GENESIS** | Verbraucherpreisindex bis zur 10-stelligen Ebene, auch einzelne Lebensmittel (z. B. „Butter“), aber **nur Index-Werte, keine Euro-Preise** | Bundesweit, monatlich | Kostenlose Webservice-API ([GENESIS](https://genesis.destatis.de/datenbank/online/statistic/61111/table/61111-0001)), dl-de/by-2.0 | 🟡 Nur geeignet, um Richtpreise hochzurechnen („Butter +8 % seit Frühjahr“) |
| **EU Agri-food Data Portal** | Erzeuger- und Großhandelspreise, Preis-Transmission entlang der Kette | EU-weit | JSON-API ([Portal](https://agridata.ec.europa.eu/extensions/dataportal/agricultural_markets.html)) | 🟡 Kaum Endkundenpreise, nur Kontext |
| **Staatliche Preisbeobachtung in Deutschland** | – | **Gibt es noch nicht.** Der Koalitionsvertrag 2025 sieht eine Preisbeobachtungsstelle vor, bisher ist nichts umgesetzt ([SPD drängt, 2026](https://foerde.news/news/spd-dr%C3%A4ngt-union-zu-einrichtung-einer-preisbeobachtungsstelle-1774628430984.html), [vzbv](https://www.vzbv.de/lebensmittelpreise)) | – | ⏳ Beobachten. Selbst wenn sie kommt, erfasst sie Margen entlang der Kette und wahrscheinlich keine Regalpreise pro Markt |

### 2.2 Open Prices: wie dünn ist „dünn“? (eigene Auswertung, Dump vom 25.09.2026)

| Kennzahl | Wert |
|---|---|
| Preise weltweit | 317.297 (davon Frankreich 211.263) |
| **Preise in Deutschland, gesamt** | **16.815** (Platz 4 nach FR, US, NO) |
| davon aus den letzten 12 Monaten | 8.222 zu 6.253 Produkten in 521 Märkten |
| Beitragende in Deutschland (12 Monate) | 270. Die **drei aktivsten liefern rund 60 %** |
| Quelle der Belege | 56 % Preisschild-Foto, 44 % Kassenbon |
| Produkte mit Preisen aus ≥ 3 Märkten | **361** |
| Städte mit den meisten Preisen (12 Monate) | Strausberg 1.629 · München 1.208 · Berlin 954 · Bielefeld 371 |
| Märkte mit ≥ 100 Preisen | 24 von 1.075 |

**Fazit:** Für einen Vergleich reicht das nicht. Für einen Hinweis wie „Dieser Artikel wurde zuletzt für 1,19 € bei Netto gesehen (Open Prices, 03/2026)“ reicht es bei einigen hundert gängigen Artikeln. Jeder Marqet-Nutzer, der beiträgt, würde die Datenbasis in Deutschland spürbar vergrößern.

### 2.3 Händler selbst

| Quelle | Daten | Bewertung |
|---|---|---|
| **Prospekt- und Angebotsseiten** (`leafletURL`) | Aktionspreise, meist als Web-Blätterkatalog | ✅ Als Link bereits in v1.0 (KONZEPT #39). Das maschinelle Auslesen ist 🟠 (siehe 3.) |
| **Online-Shops mit Regalpreisen** (REWE-Lieferservice pro Markt, Kaufland-Sortiment, dm, Rossmann) | Vollständige Regalpreise, teils marktbezogen | 🟠 Technisch der reichhaltigste Weg (so arbeiten Preisrunter und heisse-preise). Rechtlich riskant, siehe 3. Aldi Süd hat den Onlineshop zum 30.09.2025 geschlossen, Lidl verkauft online fast nur Non-Food |
| **Affiliate-Programme** (REWE bei [AWIN](https://ui.awin.com/merchant-profile/11652), bis 8 % Provision) | AWIN stellt Partnern [Produktdatenfeeds](https://www.awin.com/de/mit-awin-arbeiten/produktdatenfeed) mit Preisen bereit, wenn der Händler einen Feed anbietet | 🟡 **Einziger legaler Weg zu Regalpreisen ohne Bezahlung.** Noch offen: Gibt es einen REWE-Feed, erlaubt REWE die Nutzung in einer App, und welche Preise (online oder Markt) stehen darin? Erfordert Freigabe als Publisher. Kostenlos, aber mit Werbe-Charakter („Bei REWE bestellen“) |
| **Digitale Kassenbons** (REWE eBon als PDF per Mail, Lidl Plus mit Export) | Die echten Einkäufe des Nutzers, mit Preisen | ✅ Der Nutzer teilt seinen eigenen Bon mit Marqet (Share Sheet). Das PDF ist sauberer auszulesen als ein Foto |
| **Händler-APIs** (REWE, Lidl Plus, Edeka) | Preise und Angebote | ❌ Nur privat und reverse-engineert (bereits in MARKTANALYSE) |

### 2.4 Drittanbieter und Community

| Quelle | Daten | Zugang | Bewertung |
|---|---|---|---|
| **Preisrunter** ([preisrunter.de](https://preisrunter.de/), [API](https://preisrunter.de/api/)) | Regalpreise und Angebote für DE, AT und CH (u. a. REWE, Aldi Nord, Penny, Lidl) | Kostenlos nur für Forschung (1.000 Anfragen/Monat) und privat (200/Monat), **nur nicht-kommerziell**, Namensnennung, kein Bulk. Kommerziell ab 250 €/Monat (10.000 Anfragen) | 🟡/❌ Kostenlos ist für eine App-Store-App nicht zulässig. **Der günstigste bezahlte Weg zu Regalpreisen**, falls wir das später wollen. Die Daten stammen vermutlich aus Scraping, das Rechtsrisiko liegt dann beim Anbieter |
| **heisse-preise.io** ([GitHub](https://github.com/badlogic/heissepreise), [PyPI-Dumps](https://pypi.org/project/heisse-preise-data/)) | Tägliche Preise, historisch seit 2023 | Open Source, Dumps frei | 🟠 Vor allem Österreich. Taugt als Vorlage für Normalisierung (Einheitspreise), nicht als Quelle für DE |
| **SupermarktCheck** ([Beispiel Lidl](https://www.supermarktcheck.de/lidl/sortiment/)) | Crowdsourcing über „Preis melden“, ~9.000 Lidl-Produkte, ohne Datum | Keine API, keine offene Lizenz | ❌ Nicht nutzbar |
| **Smhaggle** | Kassenbon-Crowdsourcing mit Cashback (5 ct pro Bon) | Geschlossen | ❌ Aber ein Beleg, dass Crowdsourcing per Kassenbon funktioniert, wenn es einen Anreiz gibt |
| **marktguru, kaufDA, Apify-Actors** | Angebote | Nur inoffiziell | ❌ No-Go (bereits in MARKTANALYSE) |
| **ShopFully / Bonial** | Angebote pro PLZ | Partnerschaft, Vergütung pro Klick | Der Weg für v2.0 (bereits in MARKTANALYSE) |

### 2.5 Vorbilder im Ausland (für uns nicht nutzbar, aber ein Signal)

| Land | Modell | Relevanz |
|---|---|---|
| **Kroatien** | Seit 15.05.2025 müssen Händler **täglich maschinenlesbare Preislisten (XML/CSV)** veröffentlichen. Ab 01.10.2026 kommen Referenzpreise hinzu ([ESM](https://www.esmmagazine.com/retail/croatian-retailers-to-publish-daily-price-lists-287803), [MDev](https://mdev-digital.com/en/news/anchor-prices-and-machine-readable-price-lists-in-croatia-from-1-october-2026-what-it-means-for-your-business)) | Das Idealmodell. Kommt es in Deutschland, ist Marqets Preisfrage auf einen Schlag gelöst |
| **Ungarn** | Staatlicher „Árfigyelő“ der Wettbewerbsbehörde GVH, tägliche Pflichtmeldung, 5.000+ Produkte in 9 Ketten ([GVH](https://www.gvh.hu/en/press_room/press_releases/press-releases-2023/the-online-price-monitoring-database-of-the-gvh-and-government-measures-are-curbing-food-inflation)) | Belegt, dass Pflichtmeldungen funktionieren |
| **Griechenland** | e-Katanalotis: 1.400+ Produkte in 13 Ketten, pro Filiale ([gov.gr](https://www.gov.gr/en/ipiresies/polites-kai-kathemerinoteta/enemerose-katanaloton/e-katanalotes)) | dito |
| **Österreich** | AMA-Preistransparenzbericht (nur Aggregate) und der „Preisradar“ der Statistik Austria (Verläufe von 100+ Lebensmitteln, [ORF](https://help.orf.at/stories/3233815/)). Die BWB empfahl 2023, Scraping zu legalisieren und EAN-Codes offenzulegen, umgesetzt ist das nicht | Zeigt die Richtung, aber ohne Einzelpreise |

---

## 3. Rechtlicher Rahmen (Einordnung, keine Rechtsberatung)

- **Einzelne Preise sind Fakten** und nicht geschützt. Wer einen Preis abschreibt, verletzt nichts.
- **Datenbankherstellerrecht, § 87b UrhG:** Geschützt ist die Investition in eine Datenbank. Wer systematisch einen wesentlichen Teil entnimmt (z. B. das Sortiment eines Shops per Scraper), verletzt dieses Recht. Laut EuGH (C-762/19, *CV-Online*) kommt es darauf an, ob die Investition des Herstellers beeinträchtigt wird. Bei einer Preisvergleichs-App ist das gut vertretbar.
- **AGB:** Wenn eine Datenbank nicht geschützt ist, können AGB das Auslesen trotzdem verbieten (EuGH C-30/14, *Ryanair*). Praktisch alle Händlershops tun das.
- **Text- und Data-Mining, § 44b UrhG:** Gilt nur für Analysen und nicht, wenn der Händler maschinenlesbar widersprochen hat. Die gewonnenen Daten dürfen nicht in einer App veröffentlicht werden.
- **UWG:** Wer Bot-Schutz umgeht oder private APIs nutzt, riskiert eine Abmahnung wegen gezielter Behinderung.
- **App Review (Guideline 5.2):** Fremde Inhalte ohne Rechte können zur Ablehnung führen.
- **ODbL (Open Prices):** Anzeigen mit Namensnennung ist unproblematisch. Wenn wir Open-Prices-Daten mit eigenen Daten zu einer Datenbank verbinden und weitergeben, muss diese Datenbank ebenfalls unter ODbL stehen (Share-alike).

**Konsequenz:** Scraping bleibt für Marqet ein No-Go (wie in MARKTANALYSE). Alles, was der **Nutzer selbst** erfasst, sowie offene Daten und Affiliate-Feeds sind sauber.

---

## 4. Was realistisch in die App passt

Die Bausteine sind nach Aufwand und Risiko geordnet. Keiner braucht Geld oder einen Partner.

| Stufe | Baustein | Daten | Aufwand | Datenschutz |
|---|---|---|---|---|
| **A** | **Preisgedächtnis:** Beim Abhaken optional den Preis eintippen. Marqet merkt sich „zuletzt bezahlt“ pro Artikel und Laden | Eigene Preise | Klein: Feld am Eintrag plus Speichern im Lernmodell | Bleibt auf dem Gerät. „Keine Daten erfasst“ gilt weiter |
| **B** | **Kassenbon erfassen:** Foto per VisionKit oder REWE-eBon- bzw. Lidl-Plus-PDF über das Share Sheet. Die Positionen werden auf dem Gerät erkannt (Vision OCR) und den Listen-Artikeln zugeordnet (`ItemKeyNormalizer`) | Eigene Preise, massenhaft | Mittel: Parser pro Kette für die ~8 großen Bon-Layouts. PDF ist deutlich einfacher als ein Foto | Nur auf dem Gerät |
| **C** | **Preisschild scannen** im Laden (`DataScannerViewController`: EAN-Barcode plus Preistext) | Eigene Preise mit EAN | Klein bis mittel | Nur auf dem Gerät |
| **D** | **Richtpreise im Katalog:** Preisspanne für rund 300 Basisartikel aus `CategoryDictionary` (Discounter bis Supermarkt). Halbjährlich von Hand gepflegt aus Open Prices, eigenen Bons und Stichproben, per Destatis-Index hochgerechnet | Kuratiert | Einmalig 1–2 Tage, danach ~½ Tag pro Halbjahr | Offline im Bundle |
| **E** | **Open Prices (opt-in):** Hinweis „zuletzt gesehen“ zu einem Artikel. Optional können Nutzer ihre Bon- und Schild-Preise an Open Prices spenden | Offen, dünn | Mittel: Opt-in, Attribution, Upload braucht ein OFF-Konto | Netzwerkzugriff, Privacy-Label ändert sich (wie beim Angebote-Opt-in) |
| **F** | **Affiliate-Feed REWE prüfen** | Regalpreise (online) | Recherche, dann Entscheidung | Werbe-Charakter, passt nur bedingt zu Marqet |

**Was damit möglich wird:**

- *„Geschätzte Summe: ca. 38–45 €“* auf der Laden-Card (Richtpreise plus eigene Preise)
- *„Zuletzt bezahlt: 2,19 € bei Edeka (12.09.)“* am Eintrag
- *„Butter ist bei dir im Schnitt 40 ct günstiger bei Lidl“* aus den eigenen Bons, als ehrlicher persönlicher Vergleich
- Preisverlauf pro Artikel aus den eigenen Einkäufen

**Was damit nicht möglich wird** und deshalb auch nicht versprochen werden sollte:

- Ein marktgenauer Vergleich aller Läden in der Umgebung
- Aktuelle Aktionspreise (dafür braucht es v2.0 mit Partner)

---

## 5. Empfehlung

1. **Nicht zu viel, wenn wir es richtig schneiden:** Kein Preisvergleich, sondern ein **persönliches Preisgedächtnis** (A–C) plus **Richtpreise** (D). Beides ist kostenlos, legal und auf dem Gerät. Es passt zu „Keine Daten erfasst“ und bleibt eine Stärke, wenn später Partner-Angebote dazukommen.
2. **Reihenfolge:** A (Datenmodell für Preise, klein) → D (Richtpreise, schafft sofort sichtbaren Wert) → B (Bon-PDF zuerst, dann Foto) → C → E.
3. **Nicht machen:** Scraping, inoffizielle APIs, Preisrunter im Gratis-Tarif (nicht-kommerziell).
4. **Beobachten:** Preisbeobachtungsstelle in Deutschland, eine mögliche EU-Initiative nach kroatischem Vorbild und die Antwort auf die Frage nach einem REWE-Feed bei AWIN.

**Offene Punkte zur Entscheidung:**

- Soll das Datenmodell für Preise schon in v1.x (Stufe A), oder erst gemeinsam mit v2.0?
- Richtpreise als Spanne („ca. 1,79–2,49 €“) oder als ein Wert pro Ladentyp (Discounter/Supermarkt)?
- Open-Prices-Beitrag ja oder nein? Er bedeutet Netzwerkzugriff und ein Nutzerkonto bei OFF.

---

## Quellen

- Open Prices: [API-Doku](https://prices.openfoodfacts.org/api/docs) · [Dataset (Hugging Face)](https://huggingface.co/datasets/openfoodfacts/open-prices) · [Wiki](https://wiki.openfoodfacts.org/Prices) · [Open Food Facts Daten](https://world.openfoodfacts.org/data)
- Deutschland: [vzbv Lebensmittelpreise](https://www.vzbv.de/lebensmittelpreise) · [vzbv Pressemitteilung](https://www.vzbv.de/pressemitteilungen/hohe-lebensmittelpreise-politik-muss-fuer-transparenz-sorgen) · [WD Bundestag: Preisbeobachtungsstellen](https://www.bundestag.de/resource/blob/1209406/WD-8-0006-0013_preisbeobachtungsstellen.pdf) · [SPD drängt auf Preisbeobachtungsstelle](https://foerde.news/news/spd-dr%C3%A4ngt-union-zu-einrichtung-einer-preisbeobachtungsstelle-1774628430984.html) · [Destatis VPI Nahrungsmittel](https://www.destatis.de/DE/Themen/Wirtschaft/Konjunkturindikatoren/Preise/kpre520.html) · [Destatis Preismonitor](https://www.destatis.de/DE/Themen/Wirtschaft/Konjunkturindikatoren/Preismonitor/Preismonitor.html)
- EU: [Agri-food Data Portal](https://agridata.ec.europa.eu/extensions/dataportal/agricultural_markets.html) · [Price dashboard](https://agriculture.ec.europa.eu/data-and-analysis/markets/price-data/price-dashboard_en)
- Händler: [REWE eBon](https://www.rewe.de/service/ebon/) · [Lidl Plus Kassenbons](https://kundenservice.lidl.de/SelfServiceDE/s/article/Was-ist-der-Bereich-Meine-Kassenbons1) · [AWIN REWE](https://ui.awin.com/merchant-profile/11652) · [AWIN Produktdatenfeeds](https://www.awin.com/de/mit-awin-arbeiten/produktdatenfeed) · [ALDI SÜD](https://www.aldi-sued.de/) · [Kaufland Sortiment](https://filiale.kaufland.de/sortiment.html)
- Drittanbieter: [Preisrunter](https://preisrunter.de/) · [Preisrunter API](https://preisrunter.de/api/) · [heisse-preise (GitHub)](https://github.com/badlogic/heissepreise) · [heisse-preise-data (PyPI)](https://pypi.org/project/heisse-preise-data/) · [Mario Zechner, Year in Review 2025](https://mariozechner.at/posts/2025-12-22-year-in-review-2025/) · [SupermarktCheck](https://www.supermarktcheck.de/lidl/sortiment/) · [Smhaggle (dealdoktor)](https://www.dealdoktor.de/magazin/supermarktpreise-vergleichen/)
- Ausland: [Kroatien (ESM)](https://www.esmmagazine.com/retail/croatian-retailers-to-publish-daily-price-lists-287803) · [Kroatien ab 01.10.2026 (MDev)](https://mdev-digital.com/en/news/anchor-prices-and-machine-readable-price-lists-in-croatia-from-1-october-2026-what-it-means-for-your-business) · [Ungarn GVH](https://www.gvh.hu/en/press_room/press_releases/press-releases-2023/the-online-price-monitoring-database-of-the-gvh-and-government-measures-are-curbing-food-inflation) · [Griechenland e-Katanalotis](https://www.gov.gr/en/ipiresies/polites-kai-kathemerinoteta/enemerose-katanaloton/e-katanalotes) · [Österreich AMA-Bericht](https://www.ama.at/marktinformationen/preistransparenz/aktueller-bericht) · [Österreich Preisradar (ORF)](https://help.orf.at/stories/3233815/) · [BWB Fokuspapier Preisvergleich](https://www.bwb.gv.at/fileadmin/user_upload/Fokuspapier_Preisvergleichsplattformen_Sept_2023_barrierefrei_14.09.2023.pdf)
