# Marqet – iPhone Duo & iPad

Stand: 26.09.2026 · Ergänzt [KONZEPT.md](KONZEPT.md) · Grundlage: DuoDemo (HIG „Designing for iPhone Duo“, Apple „Preparing your app for iPhone Duo“, Figma iOS/iPadOS 27 Kit), SDK iPhoneSimulator 27.1, eigene Messung im Duo-Simulator

> **Leitidee: Zugeklappt wird eingekauft, aufgeklappt wird geplant.**
> Das Außendisplay ist das Einkaufsgerät: eine Card, große Trefferflächen, einhändig.
> Das Innendisplay ist der Planungstisch: mehrere Läden nebeneinander, Items zwischen Läden ziehen, Zuordnen auf zwei Seiten.
> Beim Auf- und Zuklappen verliert man nie den Faden, weil die aktive Card an ihrem Platz bleibt.

---

## 1. Fakten & Messungen

### 1.1 Geometrie (Figma-Kit, bestätigt im Simulator)

| Pose | Punkt | Breitenklasse | Falz |
|---|---|---|---|
| Außen, hoch | 466 × 678 | compact | – |
| Außen, quer | 678 × 466 | compact | – |
| Innen, quer (Buch aufgeklappt) | 951 × 669 | regular | senkrecht in der Mitte |
| Innen, hoch (gedreht) | 669 × 951 | regular | waagerecht in der Mitte |
| Innen, angewinkelt | wie oben | regular | Falz-Region **aktiv** |

**Eigene Messung** (Duo-Simulator, iOS 27.1, Außen hoch, DuoDemo-Tab „Geometrie“):
- Die senkrechte Leiste sitzt **trailing (rechts)**, darin Kamera, Uhr und Statussymbole oben, die Tab Bar unten.
- Zwei aktive Kamera-Verdeckungen, oberer Sicherheitsabstand 82 pt.
- Das Innendisplay ist zugeklappt aus. Posen lassen sich im Simulator nur über den Device Hub wechseln, deshalb sind Innen quer und angewinkelt noch nicht gemessen (→ Spike, §9).

### 1.2 APIs (im installierten SDK 27.1 geprüft)

| API | Verfügbar | Nutzen für Marqet |
|---|---|---|
| Senkrechte Leiste für System-Toolbars, `toolbarVerticalEdge` (Environment) | iOS 27.1 | Plus-Button, Zuordnen, Menü landen außen automatisch rechts am Daumen |
| `ToolbarOverflowMenu`, `.visibilityPriority`, `topBarPinnedTrailing` | iOS 27.0 / 27.1 | Geordneter Überlauf in der senkrechten Leiste |
| `toolbarVerticalCompressionBehavior(.prefersToolbarItems)` | iOS 27.1 | Marqet hat keine Tabs, Toolbar-Items haben Vorrang |
| `GeometryProxy.reservedRegions(kind: .division / .occlusion, options:)` → `ReservedRegion` (`frame`, `margins`, `isActive`) | iOS 27.1 | Die Lücke zwischen zwei Cards liegt exakt auf dem Falz |
| `ArrangementView` + `.arrangementViewStyle(.split.axes(…))` / `.overlay` | iOS 27.1 | Zuordnen-Screen und Küchenmodus teilen sich automatisch am Falz |
| `onHingeChange { old, new in }` → `DeviceHinge` (`status`: closed / partiallyOpen / fullyOpen, `angle`) | iOS 27.1 | Erkennt die angewinkelte Haltung (Küchenmodus) und ob ein Scharnier existiert |
| `presentationPlacement(.leading / .center / .trailing)` | iOS 27.0 | Sheets auf die linke Hälfte legen, die aktive Card rechts bleibt sichtbar |
| `toolbarVerticalBehavior(.disabled)` | iOS 27.0 | Für Sheets mit horizontal besserer Leiste (z. B. Eingabe) |
| `backgroundExtensionEffect()` | iOS 26 | Card-Header-Farbe läuft unter die senkrechte Leiste |

### 1.3 Regeln, die für Marqet die meiste Arbeit machen (aus dem DuoDemo)

1. **Nur System-Bars.** Ein eigener schwebender Plus-Button (FAB) wird *nicht* senkrecht. → Der Plus-Button wird ein **Toolbar-Item** (Änderung gegenüber KONZEPT §7.3).
2. **Jedes Toolbar-Item braucht Titel und Symbol.** Items mit eigener View (z. B. ein Listen-Umschalter als Custom View) erscheinen nie senkrecht.
3. **Layout nach Size Class und Container-Größe, nie nach Gerät.** Einzige Ausnahme ist die Anker-Seite (§2.2). Sie hängt am Scharnier und nicht an Displaymaßen.
4. **Eigene Layouts, die über den Falz reichen, müssen `ReservedRegion` lesen.** Gerade Anzahl von Cards pro Falzseite.
5. **Der Zustand überlebt das Falten:** aktive Card, Eingabetext und Fokus, Zuordnen-Fortschritt, Scrollposition.

---

## 2. Das Spread-Modell (Kern des Konzepts)

### 2.1 Seiten und Plätze

Der Pager aus KONZEPT §7.2 bleibt die einzige Struktur. Er zeigt je nach Breite **1 bis 4 Plätze** gleichzeitig:

```
Seiten:  [Unsortiert] [Rewe] [Aldi] [dm] [Weitere Läden]
Plätze:  compact = 1 · regular = 2 bis 4
```

```
plätze = clamp(⌊nutzbareBreite / 300 pt⌋, 1, 4)
Mit Falz (Duo innen): auf eine gerade Zahl abrunden (2), damit der Falz zwischen zwei Cards liegt.
```

| Kontext | Breite | Plätze |
|---|---|---|
| iPhone, Duo außen, iPad Slide Over / schmales Fenster | compact | 1 |
| Duo innen quer 951 | regular | 2 (je eine Falzseite) |
| Duo innen hoch 669 | regular | 2 (≈ 310 pt je Card) |
| iPad mini / 11″ hoch | 744–834 | 2 |
| iPad 11″ quer | ~1194 | 3 |
| iPad 13″ quer | ~1376 | 4 |

Die Plätze werden aus der **Container-Breite** berechnet, nicht aus Geräte-Typen. Damit funktionieren auch Stage Manager, frei skalierbare iPad-Fenster und künftige Geräte ohne Sonderfall.

### 2.2 Der Anker – deine Anforderung, verallgemeinert

**Anker = der Platz, auf dem die aktive Card steht.** Er bestimmt, in welche Richtung sich die Ansicht beim Aufklappen erweitert.

| Kontext | Anker | Begründung |
|---|---|---|
| **iPhone Duo** (Scharnier vorhanden) | **rechte Hälfte** (Hardware-Seite, `layoutDirectionBehavior: .fixed`) | Das Außendisplay liegt über der rechten Innenhälfte. Die aktive Card bleibt beim Aufklappen *physisch an derselben Stelle*, die neue Fläche klappt links dazu |
| **iPad** und alles ohne Scharnier | **links** (leading, in RTL gespiegelt) | Lesefluss: die aktive Card zuerst, die folgenden Läden rechts daneben |

> ⚠️ Annahme laut deiner Beschreibung: Das Außendisplay entspricht der **rechten** Innenhälfte. Wird im Spike am Device Hub bzw. auf echter Hardware verifiziert. Die Seite ist **eine Konstante** im Code und schnell umstellbar.

Die Anker-Regel bei 2 Plätzen auf dem Duo:

```
aktive Seite i  →  [ Seite i−1 | Seite i ]
aktive Seite 0  →  [ Weitere Läden | Seite 0 ]     ← deine Regel: links davon die Laden-hinzufügen-Card
```

Beispiel mit `[Unsortiert] [Rewe] [Aldi] [dm] [Weitere Läden]`:

| Zugeklappt aktiv | Aufgeklappt links | Aufgeklappt rechts (Anker) |
|---|---|---|
| Unsortiert | Weitere Läden | Unsortiert |
| Aldi | Rewe | Aldi |
| Weitere Läden | dm | Weitere Läden |

**Wischen im aufgeklappten Zustand** bewegt um **eine** Card: Die rechte Card rutscht nach links, die nächste kommt rechts herein. Damit gilt immer „rechts = aktiv“, und beim Zuklappen steht außen genau die Card, die vorher rechts war.

**„Der Fokus folgt der Hand“:** Tippt, hakt ab oder scrollt man in der **linken** Card, wird sie aktiv. Beim Zuklappen erscheint außen die Card, mit der man zuletzt gearbeitet hat. Beim nächsten Aufklappen rutscht sie auf den Anker, links steht ihre Vorgängerin. Die aktive Card bekommt einen dezenten Fokusrahmen in Laden-Farbe.

### 2.3 Übergänge

| Übergang | Verhalten |
|---|---|
| **Aufklappen** (außen → innen) | Die aktive Card bleibt an Ort und Stelle (rechte Hälfte). Die linke Card fährt vom Falz aus herein (Verschieben + Einblenden, 0,35 s, bei Reduce Motion nur Einblenden) – wie eine Seite, die aufschlägt |
| **Zuklappen** (innen → außen) | Die aktive Card füllt das Außendisplay. Eingabetext, Tastaturfokus und Scrollposition bleiben erhalten |
| **Drehen innen** (quer ↔ hoch) | Die Plätze bleiben bei 2, die aktive Card bleibt auf dem Anker |
| **iPad-Fenster verkleinern** (regular → compact) | Die Card auf dem Anker (links) wird die einzige Card |
| **Anwinkeln** innen quer (Buchhaltung) | Keine Layoutänderung, denn die Lücke lag schon auf dem Falz (§2.4). „Beim Falten nur bewegen, was nötig ist“ |
| **Anwinkeln** innen hoch (Laptop-/Tischhaltung) | Wechsel in den **Küchenmodus** (§4.3) |

### 2.4 Falz-Ausrichtung

- Liegt eine senkrechte `division`-Region im Container (auch **inaktiv**, `options: .includeInactive`), wird die Lücke zwischen den beiden Cards **exakt** auf `region.frame` gelegt, und jede Card füllt genau eine Hälfte. Weil die Ausrichtung auch im flachen Zustand gilt, springt das Layout beim Anwinkeln nicht.
- Die Kamera-Verdeckungen (`occlusion`) übernimmt der Safe-Area-Abstand. Card-Header mit `backgroundExtensionEffect()`, damit die Laden-Farbe bis unter die senkrechte Leiste reicht.
- Ohne Falz (iPad, iOS 26) werden die Plätze gleich breit, mit 16 pt Abstand.

### 2.5 Technische Umsetzung

- **`SpreadLayout` in MarqetCore** (pure Logik, getestet): Seiten + aktive Seite + Plätze + Anker → sichtbares Fenster, inklusive der Regel „links von der ersten Seite = Weitere Läden“.
- **`StorePager` (SwiftUI):** `ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:)`. Jeder Platz ist `containerWidth / plätze` breit (bzw. an den Falz gebunden). Mit Anker rechts und 2 Plätzen bekommt der Inhalt eine **Geisterseite** vorne: `[Weitere Läden (Geist)] [Unsortiert] [Rewe] …`. So kann Seite 0 auf dem rechten Platz stehen, und das native Scroll-Verhalten bleibt erhalten, ohne eigene Gesten-Physik.
- **Aktive Seite** in `@SceneStorage("activePage")` als stabile ID (`unsorted`, Store-UUID, `more`). Jede iPad-Fensterszene hat so ihre eigene aktive Card.
- **Eingabetext, Fokus-Ziel und Zuordnen-Fortschritt** liegen im `AppModel`, nicht in View-`@State`. Wird eine View beim Displaywechsel neu erzeugt, geht nichts verloren.
- **Anker-Erkennung:** `onHingeChange` liefert `DeviceHingeContext.hinge != nil` → Scharnier vorhanden → Anker rechts. Ist das nicht verfügbar (< 27.1, iPad), gilt Anker leading.
- **Mindestversion bleibt iOS 26.** Alle 27.1-APIs (`ReservedRegion`, `ArrangementView`, `onHingeChange`, senkrechte Leiste) stecken hinter `if #available(iOS 27.1, *)` in kleinen Wrappern (`FoldGeometry`, `AdaptiveSplit`, `HingeObserver`). Das Duo wird mit 27.1 ausgeliefert und hat sie also immer. Das iPad bekommt den Spread auch unter iOS 26, denn der braucht keine 27er-APIs.

---

## 3. Toolbar & Bedienelemente (Änderungen gegenüber KONZEPT §7)

| Element | Bisher | Neu (alle Geräte) | Duo außen / innen quer |
|---|---|---|---|
| **Plus-Button** | eigener Glass-FAB unten rechts | `ToolbarItem(placement: .bottomBar)` mit `Menu(primaryAction:)`: Tippen = Hinzufügen, Long Press = „Hinzufügen zu …“. `visibilityPriority(.high)` | automatisch in der senkrechten Leiste rechts, am Daumen |
| **Zuordnen** | nur Unsortiert-Card + Prompt | zusätzlich Toolbar-Item „Zuordnen“ (`tray.and.arrow.down`) mit Anzahl, sichtbar nur bei unsortierten Items | senkrecht unter dem Plus |
| **Liste / Läden / Einstellungen** | Zahnrad-Button | `ToolbarOverflowMenu` („…“): Liste wechseln, Läden verwalten, Einstellungen | ganz unten in der Leiste |
| **Karte** (v1.2) | – | Toolbar-Item „Karte“ (`map`) | senkrecht |
| **Seitenindikator** | Punkte unten | bleibt **Inhalt** (Overlay in der Safe Area, keine Toolbar). Im Spread markiert er die sichtbaren Seiten als Klammer | unverändert |
| **Laden-Chipleiste** | Keyboard-Toolbar | bleibt `ToolbarItemGroup(placement: .keyboard)`. Auf breiten Tastaturen (innen quer 951 pt) passen deutlich mehr Chips | – |

Der Screen setzt `.toolbarVerticalCompressionBehavior(.prefersToolbarItems)`. Der Listenname steht als normaler Navigationstitel, nicht als Custom View.

---

## 4. Screens je Pose

### 4.1 Außen (Einkaufen) – compact

```
┌───────────────────────────┬────┐
│ ▓▓▓ ALDI SÜD      5 offen │ 📷 │ ← Kamera/Status (Leiste trailing)
│ OBST & GEMÜSE             │    │
│ ○ Bananen                 │    │
│ BROT & BACKWAREN          │    │
│ ○ Brot                    │    │
│ MILCHPRODUKTE & EIER      │ ⊕  │ ← Hinzufügen (Daumen)
│ ○ Milch                   │ ⇣3 │ ← Zuordnen (3)
│ ○ Butter                  │ …  │ ← Überlauf
│        ◦  ●  ◦  +         │    │
└───────────────────────────┴────┘
```

Identisch zum iPhone-Layout, nur dass die Toolbar senkrecht steht. Kein eigener Code-Pfad.

### 4.2 Innen quer, flach oder als Buch angewinkelt (Planen)

```
┌──────────────────────────────┬┬──────────────────────────────┬────┐
│ ▓▓▓ REWE          3 offen    ││ ▓▓▓ ALDI SÜD      5 offen    │    │
│ OBST & GEMÜSE                ││ OBST & GEMÜSE                │    │
│ ○ Zucchini                   ││ ○ Bananen                    │ ⊕  │
│ KÜHLREGAL                    ││ BROT & BACKWAREN             │ ⇣3 │
│ ○ Frischkäse                 ││ ○ Brot                       │ …  │
│ ○ Joghurt  ─────drag───────▶ ││ ○ Milch                      │    │
│                              ││                              │    │
│            ◦ [●  ●] ◦ +      ││                              │    │
└──────────────────────────────┴┴──────────────────────────────┴────┘
       linke Hälfte             Falz        rechte Hälfte = Anker (aktiv)
```

- **Items zwischen Läden ziehen:** Ein Item per Drag von einer Card auf die andere verschieben. Der Marker wird umgeschrieben, bei Pro wird die Zuordnung gelernt. Das geht nur im Spread und ist *der* Vorteil des großen Displays.
- **Sheets** (Laden hinzufügen, Einstellungen, Zuordnen-Prompt) mit `presentationPlacement(.leading)`: Sie öffnen **auf der linken Hälfte**, die aktive Card rechts bleibt sichtbar. Grundsatz: *Die rechte Seite gehört dem Einkauf.*
- **„Linke Seite anheften“** (Card-Menü, v1.1): Die linke Card bleibt stehen, gewischt wird nur rechts. Beispiel: Unsortiert links anheften und rechts durch die Läden blättern, dann jedes Item per Drag in den passenden Laden ziehen.

### 4.3 Innen hoch, angewinkelt = Küchenmodus (v1.1)

Das Gerät steht wie ein kleiner Laptop auf der Küchenarbeitsplatte, man prüft Kühlschrank und Vorräte.

```
┌───────────────────────────────┐
│ ▓▓▓ ALDI SÜD        5 offen   │  obere Hälfte: aktive Card, nur lesen,
│ ○ Bananen  ○ Brot  ○ Milch    │  große Schrift, zweispaltig
│ ○ Butter   ○ Eier             │
╞═══════════════════════════════╡  ← Falz (waagerecht, aktiv)
│ [Aldi] [Rewe] [dm] [Markt]    │  untere Hälfte: Eingabe-Konsole
│ ┌───────────────────────────┐ │  Laden-Chips groß, Diktat-Button,
│ │ Neuer Eintrag …        🎙 │ │  zuletzt gekaufte Items als Vorschläge
│ └───────────────────────────┘ │  („Milch wieder?“)
│  Zuletzt: Milch · Eier · Kaffee│
└───────────────────────────────┘
```

- **Auslöser:** `onHingeChange` meldet `status == .partiallyOpen` **und** es gibt eine waagerechte, aktive `division`-Region. Umgesetzt mit `ArrangementView { Konsole } secondary: { Card }` und `.arrangementViewStyle(.split.axes(.vertical))`. Das System legt die Teilung selbst auf den Falz.
- **Warum v1.1:** braucht die Liste „zuletzt gekauft“ (erledigte Items der letzten Wochen, bereits als Datenquelle vorhanden) und ist ein Zusatznutzen, kein Kernfluss.

### 4.4 Zuordnen auf großen Displays

| Kontext | Darstellung |
|---|---|
| compact (iPhone, Duo außen) | wie KONZEPT §7.4: Vollbild-Sheet, Einzeln \| Board |
| regular (Duo innen, iPad) | **Zweiseitig** mit `ArrangementView(.split)`: **links** die unsortierten Items (Einzeln = großes Item, Board = Liste), **rechts** die Laden-Ziele als großes Raster mit Anzahl. Auf dem Duo liegt die Teilung automatisch auf dem Falz |
| Duo innen, Buchhaltung | wie regular. Zuordnen per Tipp ist bevorzugt, weil das Ziehen über einen angewinkelten Falz unbequem ist. Drag bleibt möglich |

```
┌──────────────────────────────┬┬──────────────────────────────┐
│  Unsortiert · 3 von 7        ││  ┌──────────┐ ┌──────────┐   │
│  ┌────────────────────────┐  ││  │ ↺ ALDI 5 │ │  REWE 3  │   │
│  │        Milch           │  ││  └──────────┘ └──────────┘   │
│  │      laktosefrei       │  ││  ┌──────────┐ ┌──────────┐   │
│  └────────────────────────┘  ││  │   dm 1   │ │  MARKT   │   │
│  Als Nächstes: Zahnpasta,    ││  └──────────┘ └──────────┘   │
│  Tomaten, Batterien          ││  [ + Laden ]  [Überspringen] │
└──────────────────────────────┴┴──────────────────────────────┘
```

Das Raster rechts hat eine **gerade Spaltenzahl** (2 bzw. 4), damit der Falz in anderen Posen nie eine Kachel teilt.

---

## 5. iPad

| Thema | Umsetzung | Version |
|---|---|---|
| **Spread** mit 2–4 Plätzen, Anker links | §2 | v1.0 |
| **Frei skalierbare Fenster / Stage Manager** | Plätze aus der Container-Breite, schmal = compact = 1 Card | v1.0 |
| **Mehrere Fenster** | eine Szene je Fenster, aktive Card per `@SceneStorage`. Daten kommen aus Erinnerungen und sind überall gleich | v1.0 |
| **Items zwischen Läden ziehen** | wie Duo §4.2 | v1.0 |
| **Zweiseitiges Zuordnen** | §4.4 | v1.0 |
| **Tastaturkurzbefehle** | ⌘N Neuer Eintrag · ⌘⇧N Neuer Laden · ⌘← / ⌘→ vorherige/nächste Card · ⌘1…⌘9 Card direkt · Leertaste abhaken · ⌘⌫ löschen · ⌘R zuordnen. Alle im ⌘-Overlay sichtbar | v1.0 |
| **Zeiger** | Hover-Effekte auf Items, Chips und Laden-Zielen; Drag mit Trackpad | v1.0 |
| **Scribble (Pencil)** | kostenlos über System-TextFields | v1.0 |
| **Drag & Drop aus anderen Apps** | Text (z. B. Rezept-Zutaten aus Safari/Notizen) auf eine Card ziehen → eine Zeile = ein Item, direkt dem Laden zugeordnet | v1.1 |
| **Sidebar** | Erst mit „mehrere Listen“ (v2.x). Bis dahin übernimmt der Seitenindikator die Navigation (antippen, scrubben, ⌘-Zahlen) | v2.x |

Ein Sonderweg für iPad nach `userInterfaceIdiom` gibt es nicht. Alles läuft über Breite und die Verfügbarkeit von Tastatur und Zeiger.

---

## 6. Weitere Ideen für das Duo – bewertet

| Idee | Nutzen | Bewertung |
|---|---|---|
| **Aufklappen mit unsortierten Items → Zuordnen-Prompt öffnet sich auf der linken Hälfte** (`presentationPlacement(.leading)`) statt als Modal über alles | Planen beginnt genau dort, wo Platz ist, die aktive Card bleibt rechts | ✅ v1.0 |
| **Items zwischen Läden ziehen** | Umsortieren ohne Menü | ✅ v1.0 |
| **Linke Seite anheften** | Zuordnen und Vergleichen im Buch-Layout | ✅ v1.1 |
| **Küchenmodus** (Tischhaltung) | freihändig ergänzen, Vorschläge „wieder kaufen?“ | ✅ v1.1 |
| **Karte + Card nebeneinander** (v1.2 „Orte“): links die Karte mit Filialen, rechts die aktive Card | Planen mit Ortsbezug, der Anker bleibt die Card | ✅ v1.2 |
| **Einkaufsrunde im Buch-Layout** (v1.3): links Route und Stopps, rechts die Card des aktuellen Stopps | Routenplanung erst mit dem großen Display wirklich komfortabel | ✅ v1.3 |
| **Live Activity beim Zuklappen** während einer aktiven Einkaufsrunde | bleibt auf dem Außendisplay präsent | v1.3 (mit Live Activity) |
| **Scharnier-Winkel als Geste** (z. B. halb zuklappen = abhaken) | Spielerei, Gefahr von Fehlauslösung | ❌ bewusst nicht |
| **Eigene Layouts pro Pose** | widerspricht der HIG („Compact + Regular deckt alle Posen ab“) | ❌ |
| **Innenkamera nutzen** (z. B. Barcode-Scan) | eher Außenkamera, eigenes Feature | später prüfen, unabhängig vom Duo |

---

## 7. Datenmodell & Architektur (Ergänzungen)

| Baustein | Ort | Zweck |
|---|---|---|
| `PageID` (`unsorted`, `store(UUID)`, `more`) | MarqetCore | stabile Seiten-IDs für SceneStorage und Pager |
| `SpreadLayout` | MarqetCore | Plätze aus Breite und Falz, sichtbares Fenster mit Anker- und Geisterseiten-Regel, Wischschritt, „Fokus folgt der Hand“ |
| `FoldGeometry` | App/DesignSystem | Wrapper um `reservedRegions`, ab iOS 27.1, sonst `nil` |
| `HingeObserver` | App | Wrapper um `onHingeChange`; liefert `hasHinge` und `isTabletop` |
| `AdaptiveSplit` | App/DesignSystem | `ArrangementView` ab 27.1, sonst `HStack`/`VStack` |
| `StorePager` | Features/Shopping | Spread-fähiger Pager (§2.5) |
| `AppModel.composer` | App | Eingabetext + Ziel-Laden + Fokus, übersteht das Falten |
| `AppModel.triage` | App | Zuordnen-Fortschritt, übersteht das Falten |

Build-Einstellungen: `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad), Deployment Target bleibt iOS 26.0, SDK 27.1.

---

## 8. Tests

**Unit (MarqetCore):** `SpreadLayout`
- Plätze je Breite, gerade Anzahl bei Falz
- Anker rechts: `[i−1 | i]` und `[Weitere Läden | 0]`
- Anker links auf dem iPad
- Wischschritt 1
- Fokuswechsel auf die linke Card
- nur eine Seite vorhanden (rechts Weitere Läden, links leer bzw. gestreckt)
- RTL gespiegelt auf dem iPad, nicht auf dem Duo

**UI-Matrix** (Duo-Simulator per Device Hub, iPad-Simulatoren):

| Pose / Gerät | prüfen |
|---|---|
| Duo außen hoch/quer | Toolbar senkrecht, Plus am Daumen, eine Card |
| Duo innen quer flach/Buch | Anker rechts, Lücke auf dem Falz, Sheets links, Drag zwischen Cards |
| Duo innen hoch flach / angewinkelt | 2 Cards bzw. Küchenmodus (v1.1) |
| Auf-/Zuklappen mit offener Tastatur | Text, Fokus und Ziel-Laden bleiben erhalten |
| Auf-/Zuklappen mit offenem Zuordnen | Fortschritt bleibt erhalten |
| iPad mini hoch, 13″ quer, Stage-Manager-Fenster schmal ↔ breit | 1–4 Plätze, Anker links, keine Sprünge |
| iPad mit Tastatur | alle Kurzbefehle |

---

## 9. Spike vor M2 (Duo)

1. **Anker-Seite:** Entspricht das Außendisplay der rechten Innenhälfte? (Device Hub bzw. Hardware)
2. **Falz-Region innen quer:** Frame flach (inaktiv) und angewinkelt (aktiv). Liegt sie bei x ≈ 475?
3. **`ScrollView` mit 2 Plätzen, Geisterseite und Falz-Lücke:** Einrasten sauber, keine Sprünge bei Größenwechsel
4. **`presentationPlacement(.leading)`** innen quer. Was passiert mit einem offenen Sheet beim Zuklappen?
5. **`onHingeChange`** im Simulator: Liefert der Device Hub Winkel und Status?
6. **Tastatur und Fokus über das Falten:** Bleibt die Tastatur offen, bleibt die Eingabezeile sichtbar?
7. **Drag & Drop über den Falz** im Buch-Modus: technisch und ergonomisch
8. **Plus-Button als `Menu(primaryAction:)`** in der senkrechten Leiste: Funktioniert der Long Press dort?
