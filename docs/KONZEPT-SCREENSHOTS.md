# Marqet – App-Store-Screenshots

Stand: 28.09.2026 · Werkzeug: `scripts/screenshots/` · Ergänzt [KONZEPT.md](KONZEPT.md)

> Ein Befehl macht aus der Demo-App fertige Werbeshots für iPhone, iPad und iPhone Duo, auf Deutsch und Englisch.
> Design: minimalistisch. Off-White, eine Überschrift in SF Pro, eine graue Zeile, darunter das Gerät.

## 1. Ablauf

```
scripts/screenshots/make.sh
  1. App bauen (Debug, Simulator)
  2. capture  Gerät × Sprache × Szene: Simulator vorbereiten, App mit -demo starten, Screenshot
              → screenshots/raw/<de|en>/<gerät>/<szene>.png
  3. frame    Überschrift + Gerät auf App-Store-Leinwand, deckendes sRGB-PNG (ASC lehnt Alpha ab)
              → screenshots/final/<de|en>/<gerät>/<szene>.png
```

| Befehl | Wirkung |
|---|---|
| `make.sh` | alles |
| `make.sh frame` | nur neu rahmen, z. B. nach Textänderungen (Sekunden) |
| `make.sh capture --devices iphone --langs en --shots 02-voice` | gezielt neu aufnehmen |
| `make.sh --devices duo-outer,duo-inner` | Duo; das Skript fragt vor jedem Gerät nach der Pose (Device Hub) |

Beide Ordner stehen in `.gitignore`.

## 2. Daten

- `-demo` lädt die Wocheneinkauf-Liste im Arbeitsspeicher (`AppModel.demo`), ohne Zugriff auf Erinnerungen.
- Die Sprache folgt `-AppleLanguages (en)`. Englisch hat eigene Einträge und die Liste „Shopping“. Die Läden bleiben deutsche Ketten (Markt: DACH).
- Szenen über bestehende Debug-Schalter: `-demo-page <katalog-key>` (Start-Card), `-demo-focus`, `-demo-voice` (spielt das Beispiel-Diktat ab), `-demo-triage`, `-demo-map`, `-widget-showcase` (`WidgetShowcaseView`: die Widgets wie auf dem Home-Bildschirm). Das Tool setzt zusätzlich `-screenshots`, damit Debug-Einblendungen wegfallen. Die Karte bekommt ihre Filter per Argument (`-mapShopCategory groceries`), sonst gelten alte Einstellungen aus dem Simulator.
- Simulator: Statusleiste 9:41, voller Akku, helles Erscheinungsbild, Standort in der Münchner Altstadt, nah an den Demo-Filialen.

## 3. Rahmen

- **Apple-Bezels:** PNGs aus den Apple Design Resources nach `scripts/screenshots/bezels/` legen (`iphone.png`, `ipad.png`, `duo-outer.png`, `duo-inner.png`). Das Tool findet den transparenten Bildschirm per Füllung von der Mitte aus. Es müssen also keine Koordinaten gepflegt werden. Bezel und Screenshot müssen dieselbe Ausrichtung haben.
- **Ohne Bezel:** schlanker, dunkler Rahmen mit Eckradius `screenCorner` und weichem Schatten.
- Texte, Farben, Größen und Wartezeiten stehen in `shots.json`. `\n` bricht die Überschrift um.

## 4. Größen

| Gerät | Simulator | Leinwand |
|---|---|---|
| iPhone 6,9″ | iPhone 18 Pro Max | 1320 × 2868 |
| iPad 13″ | iPad Air 13-inch (M4) | 2064 × 2752 |
| iPhone Duo außen / innen | iPhone Duo | **offen:** native Aufnahmegröße, bis die Größe in App Store Connect geprüft ist → `canvas` in `shots.json` eintragen |

## 5. Offen

- Englische Shots: 179 Texte haben noch keine englische Übersetzung, darunter „In der Nähe“ und die Widget-Einstellungen. Nach dem Übersetzen `make.sh` neu laufen lassen.
- iPad-Statusleiste: Datum in der Systemsprache des Simulators („Montag 28. Sept.“), auch in den englischen Shots.
- Duo-Größen in App Store Connect prüfen.
- Kundenkarte als eigene Szene (braucht Demo-Karte im `-demo`-Modus).
