# Open Prices in Marqet

Die App enthält nur die Namen und Zuordnungshilfen von 1.769 Open-Food-Facts-Kategorien (`OpenPriceCategories.json`). Sie enthält keine Preisbeobachtungen. `scripts/opendata/build_price_index.py` erzeugt diese Kategorienliste aus der offenen Taxonomie und dem Open-Prices-Datensatz; der dabei berechnete Preisindex wird nicht ins App-Bundle geschrieben.

Marqet fragt die öffentliche [Open-Prices-API](https://prices.openfoodfacts.org/api/docs) erst ab, wenn ein Preisvergleich oder die Angebotsansicht sichtbar wird. Die Anfrage enthält Kategorie und Zeitraum, aber keine Artikeltexte oder angelegten Läden. Ein bereits freigegebener Standort wird vor einer lokalen Suche auf 0,1 Grad gerundet; gesucht wird in 30 km Umkreis. Automatische Preisabrufe fordern keine Standorterlaubnis an; in der Angebotsansicht kann der Nutzer sie ausdrücklich anfordern. Ohne Standort verwendet die App Beobachtungen aus dem Land der Geräteeinstellung. Lokale Preisfunde in der Angebotsansicht setzen eine freigegebene Position voraus.

Beim ersten Onboarding lädt Marqet im Hintergrund landesweite Preise für 18 Grundartikel, ohne nach dem Standort zu fragen. Der lokale Cache hält pro Gebiet und Kategorie das Ergebnis einer Abfrage. Erst wenn die betreffende Ansicht nach mindestens 24 Stunden erneut geöffnet wird, fragt Marqet wieder ab. Fehlen lokale Preise, gelten die landesweiten. Es gibt noch keine Hintergrundaktualisierung bei geschlossener App; Überlegungen dazu stehen in [KONZEPT-HINTERGRUND.md](KONZEPT-HINTERGRUND.md).

**Guardrails** (`PriceFreshness`): Nach sieben Tagen ohne erfolgreiche Aktualisierung zeigt Marqet für die Kategorie keine Geldwerte mehr – weder Preise noch Richtwerte noch Preis-Vorschläge. Preisfunde verfallen nach zwei Tagen. Ketten, deren jüngste Beobachtung älter als 60 Tage ist, fallen aus jedem Vergleich. Offline bleiben die zuletzt geladenen Daten bis zu diesen Grenzen erhalten.

Für einen Vergleich werden reguläre Beobachtungen der letzten 90 Tage nach Kette und Einheit zusammengefasst. Bei mindestens vier Beobachtungen ist der Einstiegspreis das untere Quartil, sonst der Median. Produktpreise werden auf kg oder Liter umgerechnet. Ein einzelnes Foto ist kein belastbarer Beleg für einen Preisführer.

In der Angebotsansicht erscheinen zwischen Prospektreihen zwei Arten von Preisfunden: explizit als reduziert gemeldete Produkte mit dokumentiertem Normalpreis und mindestens 15 % Abschlag aus den letzten 14 Tagen sowie Kategorie-Preisführer, die auf mindestens zwei Beobachtungen je Kette beruhen und mindestens 10 % unter der zweitplatzierten Kette liegen. Jede Karte nennt Datum und Open Prices als Quelle. Dies sind Community-Beobachtungen, keine Zusage eines aktuell gültigen Filialangebots.

Open Prices ist unter ODbL 1.0 lizenziert. Die Bestandsaufnahme und Grenzen der Datenbasis stehen in [PREISDATEN.md](PREISDATEN.md).
