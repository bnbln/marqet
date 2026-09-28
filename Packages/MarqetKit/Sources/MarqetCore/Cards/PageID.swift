import Foundation

/// Stable identity of one page in the card pager and its scroll targets (KONZEPT §7.2).
public enum PageID: Hashable, Sendable {
    /// Map overview of the stores with open items, first page; opens the full map.
    case map
    /// Central collection of official retailer brochures, before Inbox.
    case brochures
    case unsorted
    case store(Store.ID)
    /// Hidden and suggested stores – always the last page.
    case more

    public var rawValue: String {
        switch self {
        case .map: "map"
        case .brochures: "brochures"
        case .unsorted: "unsorted"
        case .more: "more"
        case .store(let id): "store:\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "map": self = .map
        case "brochures": self = .brochures
        case "unsorted": self = .unsorted
        case "more": self = .more
        default:
            guard rawValue.hasPrefix("store:"), let id = UUID(uuidString: String(rawValue.dropFirst(6))) else {
                return nil
            }
            self = .store(id)
        }
    }

    public var storeID: Store.ID? {
        if case .store(let id) = self { id } else { nil }
    }
}
