import Foundation

/// Bundled catalog of DACH chains and generic store kinds (KONZEPT §8).
///
/// Chains are shown with a monogram and a brand-like (not identical) color – no logos.
public struct StoreCatalog: Decodable, Sendable {
    public enum Region: String, Codable, Sendable, CaseIterable {
        case germany = "DE"
        case austria = "AT"
        case switzerland = "CH"

        /// Region of the device, falling back to Germany outside DACH.
        public static var current: Region {
            Region(rawValue: Locale.current.region?.identifier ?? "") ?? .germany
        }
    }

    public struct Entry: Decodable, Hashable, Sendable, Identifiable {
        public let key: String
        public let name: String
        public let aliases: [String]
        public let regions: [Region]
        public let type: StoreType
        public let color: String
        public let monogram: String?
        public let symbol: String?
        public let leafletURL: URL?
        public let mapSearchTerms: [String]?

        public var id: String { key }

        public var storeSymbol: StoreSymbol {
            if let monogram { .monogram(monogram) } else { .systemImage(symbol ?? "cart.fill") }
        }

        public func makeStore(sortIndex: Int, id: UUID = UUID()) -> Store {
            Store(
                id: id,
                catalogKey: key,
                name: name,
                aliases: aliases,
                colorHex: color,
                symbol: storeSymbol,
                sortIndex: sortIndex,
                origin: .catalog,
                type: type
            )
        }
    }

    public let version: Int
    public let stores: [Entry]

    /// Entries available in `region`, in catalog order (chains by popularity, then generic kinds).
    public func entries(for region: Region) -> [Entry] {
        stores.filter { $0.regions.contains(region) }
    }

    public func entry(forKey key: String) -> Entry? {
        stores.first { $0.key == key }
    }

    public static func bundled() throws -> StoreCatalog {
        guard let url = Bundle.module.url(forResource: "StoreCatalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(StoreCatalog.self, from: Data(contentsOf: url))
    }
}
