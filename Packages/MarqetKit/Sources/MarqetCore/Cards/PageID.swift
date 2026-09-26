import Foundation

/// Stable identity of one page in the card pager (KONZEPT §7.2).
/// The raw value is persisted in `@SceneStorage`, so it must stay stable across launches.
public enum PageID: Hashable, Sendable {
    /// Central collection of official retailer brochures, before Inbox.
    case brochures
    case unsorted
    case store(Store.ID)
    /// Hidden and suggested stores – always the last page (stable persisted identity).
    case more

    public var rawValue: String {
        switch self {
        case .brochures: "brochures"
        case .unsorted: "unsorted"
        case .more: "more"
        case .store(let id): "store:\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
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
