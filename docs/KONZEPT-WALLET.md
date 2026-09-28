# Marqet – Kundenkarten in Apple Wallet

Stand 28.09.2026 · Recherche und Vorschlag, noch nicht umgesetzt.

> Ziel: Eine in Marqet gescannte Kundenkarte landet mit wenig Aufwand in Apple Wallet und erscheint dort
> im Laden von selbst – ohne dass Marqet sein Versprechen „Keine Daten erfasst“ bricht.

---

## 1. Was iOS 27 bringt

| Neu | Bedeutung für Marqet |
|---|---|
| **„Pass erstellen“ in Wallet** (+ → Pass erstellen): Karte mit der Kamera oder aus einem **Screenshot** per Visual Intelligence erkennen, Vorlage (Standard, Mitgliedschaft, Event) wählen, Farben anpassen. Ohne Entwickler-Account, ohne Signatur | Der Nutzer kann jede Marqet-Karte selbst übernehmen – z. B. per Screenshot des Barcode-Vollbilds. Nur der Nutzer kann das auslösen, Marqet nicht |
| **Stil „Poster Generic“** für Mitglieds- und Kundenkarten: vollflächiges Motiv, Logo, großer Barcode | Schönster Stil für signierte Marqet-Pässe (Weg B) |
| **Featured Actions** (`featuredActions`, bis zu zwei Aktionen unter dem Pass) | Z. B. „Liste bei Aldi öffnen“ → `marqet://page/store:<id>` |
| **Neue Barcodes:** EAN-13, Code 39, Codabar, ITF | EAN-13-Karten (die meisten deutschen Kundenkarten) gehen jetzt ohne Umweg. EAN-8 fehlt weiter |
| **Pass Designer** (Mac) und **Pass Builder** (Swift on Server, `buildpass`) | Pässe aus einer Vorlage am Server erzeugen und signieren |

## 2. Was nicht geht

- **Kein Pass ohne Signatur aus einer App.** Ein `.pkpass` braucht eine Signatur mit dem Pass-Type-ID-Zertifikat. Der private Schlüssel gehört nicht in die App – also braucht es einen Server. Eine API, mit der eine App „Pass erstellen“ vorbefüllt aufruft, gibt es nicht.
- **Kein offizieller Deep Link** in „Pass erstellen“. `shoebox://` öffnet Wallet, ist aber nicht dokumentiert (Risiko bei der App-Prüfung).
- **Fremde Pässe sind unsichtbar.** `PKPassLibrary` liefert nur Pässe der eigenen Pass-Type-IDs. Marqet kann nicht sehen, ob der Nutzer seine Payback-Karte schon in Wallet hat, und keine Standorte an selbst erstellte Pässe hängen.
- **Standorte bei selbst erstellten Pässen:** nicht bestätigt, dass Wallet sie im Laden vorschlägt.

## 3. Drei Wege

### A – Anleitung ohne Server (sofort machbar)

Im Kundenkarten-Vollbild ein Knopf **„Zu Apple Wallet“** → kleines Sheet:

1. „Mach einen Screenshot dieser Karte“ (oder Nummer kopieren).
2. „Öffne Wallet → + → Pass erstellen und wähle den Screenshot.“
3. Barcode-Typ nennen, falls Wallet ihn nicht erkennt (EAN-8 → Hinweis, dass Code 128 an der Kasse evtl. nicht geht).

+ keine Daten verlassen das Gerät, kein Betrieb
− mehrere Schritte, keine Vorschläge im Laden, Marqet merkt nichts davon

### B – Signierter Marqet-Pass (Server nötig)

Marqet schickt Name, Nummer, Barcode-Typ, Farbe und **bis zu 10 Filial-Koordinaten** (`locations`, aus den gemerkten Filialen) an einen kleinen Signierdienst (Pass Builder). Zurück kommt ein `.pkpass`, den Marqet mit `AddPassToWalletButton` bzw. `PKAddPassesViewController` anbietet.

+ **Wallet schlägt die Karte auf dem Sperrbildschirm vor, sobald man an einer Filiale ist**
+ ein Tipp zum Hinzufügen; Marqet weiß danach per `PKPassLibrary.containsPass`, dass sie drin ist, und öffnet sie direkt über `PKPass.passURL` – das ist der „richtige Wallet-Deep-Link“
+ Filialen später aktualisierbar (Wallet-Webservice), Poster-Generic-Design, Featured Action zurück in die Liste
− **Kartennummer verlässt das Gerät** → Datenschutz-Angabe „Keine Daten erfasst“ fällt, Datenschutzerklärung und Auftragsverarbeitung nötig
− Server, Zertifikat (jährlich), Kosten, Betrieb
− Händlerlogos im Pass: markenrechtlich heikel – besser neutral mit Name und Ladenfarbe

### C – Marqet selbst im Laden (vorhanden, ausbaubar)

Marqet erkennt die Ankunft schon (`PresenceMonitor`), die Live-Aktivität hat einen Kundenkarten-Knopf. Ausbaubar: bei Ankunft eine zeitkritische Mitteilung „Kundenkarte zeigen“, die direkt den Barcode öffnet, oder ein Steuerelement auf dem Sperrbildschirm. Das erfüllt „Karte poppt im Laden hoch“ ohne Wallet und ohne Server.

## 4. Vorschlag

1. **Jetzt: A + C.** Anleitung im Kundenkarten-Vollbild und die Ankunfts-Mitteilung. Kein Server, Datenschutz bleibt.
2. **Später, nach Entscheidung: B** als Pro-Funktion, wenn ein Signierdienst gewollt ist. Die Standorte gibt es nur hier.

## 5. Offene Fragen

- Ist ein eigener Signierdienst denkbar – und darf die Kartennummer dafür das Gerät verlassen?
- Soll „Zu Apple Wallet“ (A) sofort gebaut werden, und wenn ja: mit dem undokumentierten `shoebox://` zum Öffnen von Wallet oder nur mit Text?
- Ankunfts-Mitteilung mit Kundenkarte (C): zusätzlich zur Live-Aktivität oder statt ihr?

## Quellen

- [What's new in Wallet – WWDC26](https://developer.apple.com/videos/play/wwdc2026/209/)
- [MacRumors: iOS 27 Wallet „Create a Pass“](https://www.macrumors.com/2026/06/08/ios-27-wallet-create-pass/)
- [9to5Mac: Apple Wallet in iOS 27](https://9to5mac.com/2026/09/25/apple-wallet-in-ios-27-adds-feature-thats-been-on-my-wishlist-for-years/)
- [Michael Tsai: iOS 27 Custom Wallet Passes](https://mjtsai.com/blog/2026/05/06/ios-27-custom-wallet-passes/)
- [Poster Generic Pass (bleepingswift)](https://bleepingswift.com/blog/poster-generic-pass-wallet-ios-27)
- [Anatomy of an Apple Wallet Pass (WalletWallet)](https://www.walletwallet.dev/blog/anatomy-of-an-apple-wallet-pass/)
