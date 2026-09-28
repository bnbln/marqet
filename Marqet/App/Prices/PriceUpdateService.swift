import Foundation
import MarqetCore

/// Open Prices observations fetched only for categories the app is about to show.
enum PriceUpdateService {
    static let lookbackDays = 90
    private static let pageSize = 100
    private static let maximumPagesPerQuery = 25

    /// An already authorized position is rounded to roughly 10 km before it leaves the device.
    /// Without location permission, the app uses country-level observations for comparisons.
    struct Area: Hashable, Sendable {
        let center: GeoPoint?
        let radiusKilometers = 30

        init(location: GeoPoint?) {
            center = location.map {
                GeoPoint(latitude: ($0.latitude * 10).rounded() / 10,
                         longitude: ($0.longitude * 10).rounded() / 10)
            }
        }

        var key: String {
            guard let center else { return "country" }
            return "\(center.latitude),\(center.longitude),\(radiusKilometers)"
        }
    }

    struct PriceFind: Codable, Hashable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case observedDiscount, priceLeader }

        let id: String
        let categoryTag: String
        let title: String
        let store: String
        let amount: Double
        let unit: PriceIndex.Unit?
        let date: String
        let kind: Kind
        let discountPercent: Int?
        let sourcePriceID: Int?

        var sourceURL: URL? {
            sourcePriceID.flatMap { URL(string: "https://prices.openfoodfacts.org/prices/\($0)") }
        }
    }

    struct Result: Sendable {
        let prices: [PriceIndex.ChainPrice]
        let finds: [PriceFind]
    }

    struct Cache: Codable {
        var entries: [String: Entry] = [:]

        struct Entry: Codable {
            let checkedAt: Date
            let prices: [PriceIndex.ChainPrice]
            let finds: [PriceFind]?
        }

        static func key(region: StoreCatalog.Region, area: Area, tag: String) -> String {
            "\(region.rawValue):\(area.key):\(tag)"
        }

        static var fileURL: URL? {
            guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            return directory.appendingPathComponent("OpenPriceUpdates.json")
        }

        static func load() -> Cache {
            guard let fileURL, let data = try? Data(contentsOf: fileURL),
                  let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
            return cache
        }

        func save() throws {
            guard let fileURL = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: fileURL, options: .atomic)
        }
    }

    enum RefreshError: Error {
        case invalidResponse
        case tooManyPages
    }

    static func fetch(tag: String, categoryName: String, region: StoreCatalog.Region,
                      area: Area, catalog: StoreCatalog) async throws -> Result {
        let since = Calendar(identifier: .gregorian).date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let date = since.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        var groups: [GroupKey: [(value: Double, date: String)]] = [:]
        var discounts: [PriceFind] = []

        for filter in ["category_tag", "product__categories_tags__contains"] {
            var page = 1
            while true {
                try Task.checkCancellation()
                var url = URLComponents(string: "https://prices.openfoodfacts.org/api/v1/prices")!
                var query = [
                    URLQueryItem(name: filter, value: tag),
                    URLQueryItem(name: "date__gte", value: date),
                    URLQueryItem(name: "size", value: String(pageSize)),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "order_by", value: "-date"),
                ]
                if let center = area.center {
                    query += [URLQueryItem(name: "lat", value: String(center.latitude)),
                              URLQueryItem(name: "lon", value: String(center.longitude)),
                              URLQueryItem(name: "radius_km", value: String(area.radiusKilometers))]
                }
                url.queryItems = query
                var request = URLRequest(url: url.url!)
                request.timeoutInterval = 20
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Marqet/1.0 (price lookup)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                    throw RefreshError.invalidResponse
                }
                let result = try JSONDecoder().decode(PricePage.self, from: data)
                guard result.pages <= maximumPagesPerQuery else { throw RefreshError.tooManyPages }

                for observation in result.items {
                    guard observation.duplicateOf == nil,
                          observation.location?.osmAddressCountryCode == region.rawValue,
                          observation.currency == (region == .switzerland ? "CHF" : "EUR"),
                          observation.type == (filter == "category_tag" ? "CATEGORY" : "PRODUCT"),
                          (filter == "category_tag" ? observation.categoryTag == tag : observation.product?.categoriesTags?.contains(tag) == true),
                          let brand = observation.location?.osmBrand ?? observation.location?.osmName,
                          let chain = ChainRecognizer.entry(forPlaceNamed: brand, in: catalog.stores),
                          let (unit, value) = observation.unitPrice,
                          let recordedAt = observation.date else { continue }
                    groups[GroupKey(store: chain.key, unit: unit), default: []].append((value, recordedAt))
                    if area.center != nil, observation.type == "PRODUCT",
                       let regular = observation.priceWithoutDiscount,
                       let current = observation.price, observation.priceIsDiscounted == true,
                       regular > current, current > 0,
                       let productName = observation.product?.productName, !productName.isEmpty,
                       let id = observation.id,
                       let observed = Self.day(recordedAt), observed >= Date().addingTimeInterval(-14 * 24 * 60 * 60) {
                        let share = (regular - current) / regular
                        if share >= 0.15 {
                            discounts.append(PriceFind(
                                id: "discount:\(id)", categoryTag: tag, title: productName,
                                store: chain.key, amount: current, unit: nil, date: recordedAt,
                                kind: .observedDiscount, discountPercent: Int((share * 100).rounded()), sourcePriceID: id
                            ))
                        }
                    }
                }
                guard page < result.pages else { break }
                page += 1
            }
        }

        let prices = groups.map { key, observations in
            let values = observations.map(\.value).sorted()
            let typical = values.count < 4 ? Self.quantile(values, at: 0.5) : Self.quantile(values, at: 0.25)
            return PriceIndex.ChainPrice(
                store: key.store, unit: key.unit, typical: Self.cents(typical),
                median: Self.cents(Self.quantile(values, at: 0.5)),
                low: Self.cents(values[0]), high: Self.cents(values[values.count - 1]),
                count: values.count, latest: observations.map(\.date).max() ?? ""
            )
        }
        var finds = discounts.sorted {
            ($0.discountPercent ?? 0, $0.date) > ($1.discountPercent ?? 0, $1.date)
        }
        if area.center != nil {
            let byUnit = Dictionary(grouping: prices, by: \.unit)
            for (unit, rows) in byUnit {
                let reliable = rows.filter { $0.count >= 2 }.sorted { $0.typical < $1.typical }
                guard reliable.count >= 2, reliable[1].typical > 0,
                      reliable[0].typical <= reliable[1].typical * 0.9,
                      let lastSeen = day(reliable[0].latest),
                      lastSeen >= Date().addingTimeInterval(-30 * 24 * 60 * 60) else { continue }
                finds.append(PriceFind(
                    id: "leader:\(tag):\(unit.rawValue):\(reliable[0].store)",
                    categoryTag: tag, title: categoryName, store: reliable[0].store,
                    amount: reliable[0].typical, unit: unit, date: reliable[0].latest,
                    kind: .priceLeader, discountPercent: nil, sourcePriceID: nil
                ))
            }
        }
        return Result(prices: prices, finds: Array(finds.prefix(6)))
    }

    private static func day(_ value: String) -> Date? {
        try? Date(value, strategy: .iso8601.year().month().day().dateSeparator(.dash))
    }

    private static func cents(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    /// Same inclusive quantile used by the offline index builder.
    private static func quantile(_ sorted: [Double], at share: Double) -> Double {
        let position = Double(sorted.count - 1) * share
        let lower = Int(position)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[min(lower + 1, sorted.count - 1)] - sorted[lower]) * fraction
    }

    private struct GroupKey: Hashable {
        let store: String
        let unit: PriceIndex.Unit
    }

    private struct PricePage: Decodable {
        let pages: Int
        let items: [Observation]
    }

    private struct Observation: Decodable {
        let id: Int?
        let type: String
        let categoryTag: String?
        let currency: String?
        let price: Double?
        let priceWithoutDiscount: Double?
        let priceIsDiscounted: Bool?
        let pricePer: String?
        let duplicateOf: Int?
        let date: String?
        let location: Location?
        let product: Product?

        enum CodingKeys: String, CodingKey {
            case id, type, currency, price, date, location, product
            case categoryTag = "category_tag"
            case priceWithoutDiscount = "price_without_discount"
            case priceIsDiscounted = "price_is_discounted"
            case pricePer = "price_per"
            case duplicateOf = "duplicate_of"
        }

        var unitPrice: (PriceIndex.Unit, Double)? {
            guard let value = priceIsDiscounted == true ? priceWithoutDiscount : price,
                  value.isFinite, value > 0 else { return nil }
            if type == "CATEGORY" {
                return switch pricePer {
                case "KILOGRAM": (.kilogram, value)
                case "UNIT": (.piece, value)
                default: nil
                }
            }
            guard let product, let quantity = product.productQuantity, quantity.isFinite, quantity > 0 else { return nil }
            let measure: (PriceIndex.Unit, Double)? = switch product.productQuantityUnit?.lowercased() {
            case "g": (.kilogram, quantity / 1000)
            case "kg": (.kilogram, quantity)
            case "ml": (.liter, quantity / 1000)
            case "cl": (.liter, quantity / 100)
            case "l": (.liter, quantity)
            default: nil
            }
            guard let (unit, amount) = measure, (0.02...25).contains(amount) else { return nil }
            return (unit, value / amount)
        }
    }

    private struct Location: Decodable {
        let osmBrand: String?
        let osmName: String?
        let osmAddressCountryCode: String?

        enum CodingKeys: String, CodingKey {
            case osmBrand = "osm_brand"
            case osmName = "osm_name"
            case osmAddressCountryCode = "osm_address_country_code"
        }
    }

    private struct Product: Decodable {
        let productName: String?
        let productQuantity: Double?
        let productQuantityUnit: String?
        let categoriesTags: [String]?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case productQuantity = "product_quantity"
            case productQuantityUnit = "product_quantity_unit"
            case categoriesTags = "categories_tags"
        }
    }
}
