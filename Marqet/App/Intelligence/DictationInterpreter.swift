import Foundation
import FoundationModels
import MarqetCore

/// Reads a shopping dictation with Apple Intelligence (Pro, KONZEPT §3.3).
///
/// Streams the growing list while the model writes, so rows can appear during generation.
/// Guided generation: `laden` can only be one of the offered store names or "keiner", and each
/// entry ends with `laden` – an entry is emitted once its store is complete.
extension FoundationModelsService {
    private static let noStore = "keiner"

    func interpretDictation(_ transcript: String, stores: [String], language: VoiceLanguage) -> AsyncThrowingStream<[SpokenEntry], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard isAvailable, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continuation.finish()
                        return
                    }
                    let choices = (stores + [Self.noStore]).uniqued()
                    let entry = DynamicGenerationSchema(name: "Eintrag", properties: [
                        .init(name: "artikel", description: language == .english
                                ? "The item without quantity, as spoken"
                                : "Der Artikel ohne Menge, großgeschrieben, wie gesprochen",
                              schema: DynamicGenerationSchema(type: String.self)),
                        .init(name: "menge", description: language == .english
                                ? "Quantity with unit, e.g. “500 g” or “10”, otherwise empty"
                                : "Menge mit Einheit, z. B. „500 g“ oder „10“, sonst leer",
                              schema: DynamicGenerationSchema(type: String.self), isOptional: true),
                        .init(name: "laden", schema: DynamicGenerationSchema(name: "Laden", anyOf: choices)),
                    ])
                    let root = DynamicGenerationSchema(name: "Einkauf", properties: [
                        .init(name: "eintraege", schema: DynamicGenerationSchema(arrayOf: entry, maximumElements: 40)),
                    ])
                    let schema = try GenerationSchema(root: root, dependencies: [])
                    let instructions = language == .english
                        ? Self.englishInstructions(stores: stores)
                        : Self.germanInstructions(stores: stores)
                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(
                        to: (language == .english ? "Dictation: " : "Diktat: ") + transcript,
                        schema: schema,
                        options: GenerationOptions(samplingMode: .greedy)
                    )
                    let valid = Set(choices)
                    let spokenWords = VoiceTokenizer.words(in: transcript)
                    let heard = Set(spokenWords)
                    for try await snapshot in stream {
                        let entries = Self.entries(in: snapshot.rawContent, validStores: valid)
                        continuation.yield(entries.filter { Self.wasSpoken($0, heard: spokenWords) }
                            .map { Self.droppingUnspokenDetail(from: $0, heard: heard) })
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func germanInstructions(stores: [String]) -> String {
        """
        Du liest ein gesprochenes Einkaufs-Diktat und machst daraus Einträge für Einkaufslisten.
        Regeln:
        - Ein Eintrag pro Artikel. Füllwörter („ich brauche“, „ah“, „will … kaufen“) gehören nicht dazu.
        - Im Diktat fehlen oft Kommas: „Butter Zwiebeln“ sind zwei Artikel, „Rote Bete“ ist einer.
        - Mengen und Einheiten kommen in „menge“ („500 g“, „10“, „2 Packungen“), nicht in „artikel“.
        - Gesprochene Eigenschaften bleiben beim Artikel, nach einem Komma: „Milch laktosefrei“ → „Milch, laktosefrei“.
          Erfinde keine Eigenschaften, die nicht gesagt wurden.
        - Übernimm Mengen und Einheiten wie gesprochen und rechne nichts um.
        - „laden“ ist der Laden, bei dem der Artikel gekauft werden soll. Ein Laden direkt hinter einem Artikel gilt
          nur für diesen Artikel („HDMI-Kabel von Mediamarkt, Kuchen“ → Kuchen ohne Laden). Am Ende einer Aufzählung
          gilt er für die ganze Aufzählung („Milch, Butter und Eier bei Rewe“), ebenso ein eigener Satzteil
          („10 Eier, die will ich auf dem Markt kaufen“).
        - Ein Satz, der nur einen Laden nennt („Die hole ich bei Rewe.“), gilt für die Artikel des Satzes davor.
        - Ein Punkt steht auch dort, wo eine Sprechpause war. Ein Laden in einem Satz mit eigenen Artikeln gilt nicht
          rückwirkend für den Satz davor.
        - Jeder gesagte Artikel ist genau ein Eintrag: „Milch, Butter“ sind zwei Einträge, nie zusätzlich „Milchbutter“.
        - Ein Laden, der vorab angekündigt wird („Bei Rewe brauche ich einiges.“), gilt für die folgenden Artikel,
          bis ein anderer Laden genannt wird. Ebenso Sätze mit „und“, „auch“, „genau wie“ oder reine Aufzählungen.
        - Ohne erkennbaren Laden: „\(noStore)“. Erfinde keine Läden.
        - Korrekturen gelten: „doch keine Milch“ entfernt die Milch, „nein, drei Eier“ ändert die Menge.
        Läden: \(stores.joined(separator: ", "))

        Beispiel: „Ich brauche 10 Eier und will sie auf dem Markt kaufen, genau wie Suppengrün. Bei Rewe Hackfleisch.
        Ich brauche noch Milch. Die hole ich bei Aldi. Brot. Batterien von Mediamarkt, Kuchen.“
        → Eier (10, Markt), Suppengrün (Markt), Hackfleisch (Rewe), Milch (Aldi), Brot (\(noStore)),
        Batterien (Mediamarkt), Kuchen (\(noStore))
        """
    }

    private static func englishInstructions(stores: [String]) -> String {
        """
        You read a spoken shopping dictation and turn it into shopping list entries.
        Rules:
        - One entry per item, written in English as spoken. Filler words (“I need”, “oh”, “I want to buy”) are not items.
        - Dictations often lack commas: “butter onions” are two items, “peanut butter” is one.
        - Quantities and units go into “menge” (“500 g”, “10”, “2 packs”), not into “artikel”.
        - Spoken properties stay with the item, after a comma: “lactose-free milk” → “Milk, lactose-free”.
          Never add properties that were not said.
        - Keep quantities and units as spoken (“two pounds” → “2 lb”) and never convert them.
        - “laden” is the store where the item should be bought. A store right after an item applies to that item
          only (“HDMI cable from Mediamarkt, cake” → cake without store). At the end of an enumeration it applies to
          the whole enumeration (“milk, butter and eggs at Rewe”), and so does a clause of its own
          (“10 eggs, I'll get them at the market”).
        - A sentence that only names a store (“Get them at Rewe.”) applies to the items of the sentence before.
        - A period also marks a pause in speech. A store in a sentence with items of its own never applies back to
          the sentence before.
        - Every spoken item is exactly one entry: “milk, butter” are two entries, never also “milkbutter”.
        - A store announced first (“At Rewe I need a few things.”) applies to the following items until another
          store is named. So do sentences starting with “and”, “also”, “as well as” and bare enumerations.
        - Without a recognizable store: “\(noStore)”. Never invent stores. Store names stay as listed.
        - Corrections count: “actually no milk” removes the milk, “no, three eggs” changes the quantity.
        Stores: \(stores.joined(separator: ", "))

        Example: “I need 10 eggs from the market, as well as soup greens. At Rewe ground beef.
        I also need milk. Get it at Aldi.”
        → Eggs (10, Markt), Soup greens (Markt), Ground beef (Rewe), Milk (Aldi)
        """
    }

    /// An entry needs a word the user said (compared by its first four letters: "Eiern" ~ "Eier"),
    /// and none of its words may be several spoken words glued together: "Milchbutter" from
    /// "Milch, Butter" shares "milc" with "Milch" but was never said.
    private static func wasSpoken(_ entry: SpokenEntry, heard: [String]) -> Bool {
        let words = VoiceTokenizer.words(in: entry.name)
        let glued = words.contains { word in
            !heard.contains(word) && VoiceDraft.isConcatenation(word, of: heard)
        }
        guard !glued else { return false }
        let stems = Set(heard.map { String($0.prefix(4)) })
        return words.contains { $0.count >= 3 && stems.contains(String($0.prefix(4))) }
    }

    /// "Kartoffeln, mehligkochend" stays only if "mehligkochend" was said – the small model
    /// sometimes copies details from its instructions.
    private static func droppingUnspokenDetail(from entry: SpokenEntry, heard: Set<String>) -> SpokenEntry {
        guard let comma = entry.name.firstIndex(of: ",") else { return entry }
        let detail = VoiceTokenizer.words(in: String(entry.name[comma...]))
        guard !detail.isEmpty, !detail.allSatisfy(heard.contains) else { return entry }
        var trimmed = entry
        trimmed.name = String(entry.name[..<comma]).trimmingCharacters(in: .whitespaces)
        return trimmed
    }

    /// Complete entries of a (partial) snapshot: those whose `laden` is one of the choices.
    private static func entries(in content: GeneratedContent, validStores: Set<String>) -> [SpokenEntry] {
        guard case .structure(let properties, _) = content.kind,
              case .array(let items)? = properties["eintraege"]?.kind else { return [] }
        return items.compactMap { item in
            guard case .structure(let fields, _) = item.kind,
                  case .string(let name)? = fields["artikel"]?.kind,
                  case .string(let store)? = fields["laden"]?.kind,
                  validStores.contains(store) else { return nil }
            var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            // Titles start uppercase like the rules' ("eggs" → "Eggs").
            trimmed = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
            var quantity: String?
            if case .string(let value)? = fields["menge"]?.kind {
                let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                quantity = value.isEmpty ? nil : value
            }
            return SpokenEntry(name: trimmed, quantity: quantity, storeName: store == noStore ? nil : store)
        }
    }
}
