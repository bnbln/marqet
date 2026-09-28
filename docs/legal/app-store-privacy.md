# App Store Connect: Datenschutzangaben („Nutrition Label“)

| Frage | Antwort | Begründung |
|---|---|---|
| Erfasst ihr oder Drittanbieter Daten dieser App? | **Nein: „Keine Daten erfasst“** | Kein Server, keine SDKs von Drittanbietern, keine Analyse. Erinnerungen, Standort, Kamera-Scan, Kundenkarten und Apple Intelligence werden nur auf dem Gerät bzw. von Apple verarbeitet; Apple-Dienste zählen nicht als Erfassung durch den Entwickler. |
| Tracking | Nein | Kein IDFA, kein ATT-Dialog. |
| Privacy Manifest | `Marqet/Resources/PrivacyInfo.xcprivacy` | UserDefaults CA92.1, keine erfassten Datentypen. |
| Datenschutz-URL | [URL zu datenschutz.md] | Pflichtfeld. |
| Support-URL | [URL zu support.md] | Pflichtfeld. |

**Review-Hinweis (Notes for Review), Vorschlag:**
Marqet organizes an existing Apple Reminders list by store. Please allow Reminders access when asked; the app creates a list "Einkaufen" if needed. Store logos are shown only to identify the stores where the user shops (nominative use); Marqet is not affiliated with these retailers, as stated in the app. Marqet Pro is a non-consumable, family-shareable in-app purchase; "Restore Purchases" is in Settings › Marqet Pro.
