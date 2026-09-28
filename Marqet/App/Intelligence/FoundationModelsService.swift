import Foundation
import FoundationModels
import MarqetCore

struct IntelligenceStore: Sendable {
    let name: String
    let kind: String
}

/// On-device suggestions (KONZEPT §6.2). Everything is optional: callers fall back silently.
protocol IntelligenceService: Sendable {
    var isAvailable: Bool { get }
    /// Item title → store name, only for items the model could place.
    func suggestStores(for titles: [String], stores: [IntelligenceStore]) async throws -> [String: String]
    /// Item title → category.
    func categorize(_ titles: [String]) async throws -> [String: ItemCategory]
    /// A spoken shopping list → entries with stores, streamed while the model writes (KONZEPT §3).
    func interpretDictation(_ transcript: String, stores: [String], language: VoiceLanguage) -> AsyncThrowingStream<[SpokenEntry], any Error>
}

extension IntelligenceService {
    func interpretDictation(_ transcript: String, stores: [String], language: VoiceLanguage) -> AsyncThrowingStream<[SpokenEntry], any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// Apple Intelligence via Foundation Models, with guided generation.
///
/// Store names and item titles are only known at runtime, so the schema is built with
/// `DynamicGenerationSchema`: the model can only answer with existing stores (or "unbekannt")
/// and must echo the item titles exactly – no invented stores, no drifting titles.
struct FoundationModelsService: IntelligenceService {
    static let batchSize = 15
    private static let unknown = "unbekannt"

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func suggestStores(for titles: [String], stores: [IntelligenceStore]) async throws -> [String: String] {
        guard isAvailable, !stores.isEmpty else { return [:] }
        let storeList = stores.map { "- \($0.name) (\($0.kind))" }.joined(separator: "\n")
        let instructions = """
            Du ordnest Einkaufslisten-Einträge den Läden eines Haushalts in Deutschland, Österreich oder der Schweiz zu.
            Wähle für jeden Eintrag den Laden, in dem man ihn typischerweise kauft. Drogerieartikel gehören in eine Drogerie,
            Lebensmittel in einen Supermarkt oder Discounter. Antworte mit "\(Self.unknown)", wenn keiner passt.
            Die Läden:
            \(storeList)
            """
        var result: [String: String] = [:]
        for batch in titles.uniqued().chunked(into: Self.batchSize) {
            let answers = try await ask(
                instructions: instructions,
                titles: batch,
                valueName: "laden",
                choices: stores.map(\.name) + [Self.unknown]
            )
            for (title, store) in answers where store != Self.unknown { result[title] = store }
        }
        return result
    }

    func categorize(_ titles: [String]) async throws -> [String: ItemCategory] {
        guard isAvailable else { return [:] }
        let instructions = """
            Du ordnest Einkaufslisten-Einträge einer Supermarkt-Kategorie zu.
            Kategorien: produce = Obst und Gemüse, bakery = Brot und Backwaren, dairyEggs = Milchprodukte und Eier,
            cheese = Käse, meat = Fleisch und Wurst, fish = Fisch, breakfast = Frühstück und Aufstriche,
            pantry = Vorrat (Nudeln, Reis, Konserven, Gewürze), baking = Backzutaten, snacks = Snacks und Süßes,
            frozen = Tiefkühl, beverages = Getränke ohne Alkohol, alcohol = Wein, Bier und Spirituosen,
            personalCare = Drogerie und Pflege, household = Haushalt, baby = Baby, pet = Tier, other = Sonstiges.
            """
        var result: [String: ItemCategory] = [:]
        for batch in titles.uniqued().chunked(into: Self.batchSize) {
            let answers = try await ask(
                instructions: instructions,
                titles: batch,
                valueName: "kategorie",
                choices: ItemCategory.allCases.map(\.rawValue)
            )
            for (title, raw) in answers {
                if let category = ItemCategory(rawValue: raw) { result[title] = category }
            }
        }
        return result
    }

    /// `{ "antworten": [ { "eintrag": <one of titles>, "<valueName>": <one of choices> } ] }`
    private func ask(instructions: String, titles: [String], valueName: String, choices: [String]) async throws -> [String: String] {
        let answer = DynamicGenerationSchema(name: "Antwort", properties: [
            .init(name: "eintrag", schema: DynamicGenerationSchema(name: "Eintrag", anyOf: titles)),
            .init(name: valueName, schema: DynamicGenerationSchema(name: valueName.capitalized, anyOf: choices)),
        ])
        let root = DynamicGenerationSchema(name: "Antworten", properties: [
            .init(name: "antworten", schema: DynamicGenerationSchema(arrayOf: answer, minimumElements: titles.count, maximumElements: titles.count)),
        ])
        let schema = try GenerationSchema(root: root, dependencies: [])
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Einträge:\n" + titles.map { "- \($0)" }.joined(separator: "\n")
        let response = try await session.respond(to: prompt, schema: schema)

        struct Payload: Decodable { let antworten: [[String: String]] }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(response.content.jsonString.utf8))
        var result: [String: String] = [:]
        for entry in payload.antworten {
            if let title = entry["eintrag"], let value = entry[valueName] { result[title] = value }
        }
        return result
    }
}

/// Always unavailable – for tests and devices without Apple Intelligence.
struct UnavailableIntelligence: IntelligenceService {
    var isAvailable: Bool { false }
    func suggestStores(for titles: [String], stores: [IntelligenceStore]) async throws -> [String: String] { [:] }
    func categorize(_ titles: [String]) async throws -> [String: ItemCategory] { [:] }
}

extension Array where Element: Hashable {
    /// Guided generation's `anyOf` needs distinct choices.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
