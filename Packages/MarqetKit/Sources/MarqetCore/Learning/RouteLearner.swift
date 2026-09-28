import Foundation

/// A check-off inside a store card, the raw material for walking-order learning.
public struct CheckOff: Hashable, Sendable, Codable {
    public let storeID: Store.ID
    public let itemKey: String
    public let category: ItemCategory
    public let date: Date

    public init(storeID: Store.ID, itemKey: String, category: ItemCategory, date: Date) {
        self.storeID = storeID
        self.itemKey = itemKey
        self.category = category
        self.date = date
    }
}

/// Groups check-offs into shopping sessions per store (KONZEPT §6.4).
///
/// A session is a run of check-offs in one store with gaps under `maximumGap`. Only sessions
/// with at least `minimumCheckOffs` count – that filters out ticking things off at home.
public struct ShoppingSessionTracker: Sendable, Codable {
    public static let maximumGap: TimeInterval = 20 * 60
    public static let minimumCheckOffs = 3

    public private(set) var pending: [Store.ID: [CheckOff]] = [:]

    public init() {}

    /// Records a check-off and returns sessions that ended because of it (a gap in that store).
    public mutating func record(_ checkOff: CheckOff) -> [[CheckOff]] {
        var finished: [[CheckOff]] = []
        if let last = pending[checkOff.storeID]?.last, checkOff.date.timeIntervalSince(last.date) > Self.maximumGap {
            finished.append(pending.removeValue(forKey: checkOff.storeID) ?? [])
        }
        pending[checkOff.storeID, default: []].append(checkOff)
        return finished.filter { $0.count >= Self.minimumCheckOffs }
    }

    /// Undo of a check-off within the undo window.
    public mutating func remove(itemKey: String, storeID: Store.ID) {
        guard var list = pending[storeID], let index = list.lastIndex(where: { $0.itemKey == itemKey }) else { return }
        list.remove(at: index)
        pending[storeID] = list.isEmpty ? nil : list
    }

    /// Ends all sessions whose last check-off is older than `maximumGap`.
    public mutating func flushExpired(now: Date) -> [[CheckOff]] {
        var finished: [[CheckOff]] = []
        for (storeID, list) in pending {
            guard let last = list.last, now.timeIntervalSince(last.date) > Self.maximumGap else { continue }
            pending[storeID] = nil
            finished.append(list)
        }
        return finished.filter { $0.count >= Self.minimumCheckOffs }
    }
}

/// Learns positions from the order things were checked off (KONZEPT §6.4).
public enum RouteLearner {
    /// Rank of each key in a session, normalized to 0…1. Repeated keys use their mean rank.
    public static func relativePositions<Key: Hashable>(_ sequence: [Key]) -> [Key: Double] {
        guard sequence.count > 1 else { return sequence.first.map { [$0: 0.5] } ?? [:] }
        var ranks: [Key: [Double]] = [:]
        let denominator = Double(sequence.count - 1)
        for (index, key) in sequence.enumerated() {
            ranks[key, default: []].append(Double(index) / denominator)
        }
        return ranks.mapValues { $0.reduce(0, +) / Double($0.count) }
    }

    /// Moving average: fast while there is little data, then α = 0.3. Manual positions move half as fast.
    public static func updated(_ existing: OrderPosition?, observed: Double) -> OrderPosition {
        guard var position = existing else { return OrderPosition(value: observed, samples: 1) }
        var alpha = position.samples < 3 ? 1 / Double(position.samples + 1) : 0.3
        if position.isManual { alpha /= 2 }
        position.value = position.value * (1 - alpha) + observed * alpha
        position.samples += 1
        return position
    }

    public static func learn<Key: Hashable>(_ sequence: [Key], into positions: [Key: OrderPosition]) -> [Key: OrderPosition] {
        var result = positions
        for (key, observed) in relativePositions(sequence) {
            result[key] = updated(result[key], observed: observed)
        }
        return result
    }

    /// Category order from a session: each category at the mean rank of its items.
    public static func categorySequence(of session: [CheckOff]) -> [ItemCategory] {
        session.map(\.category)
    }

    /// Positions of manually reordered categories, evenly spread in the given order.
    public static func manualPositions(for order: [ItemCategory]) -> [ItemCategory: OrderPosition] {
        let denominator = Double(max(order.count - 1, 1))
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { index, category in
            (category, OrderPosition(value: Double(index) / denominator, samples: 1, isManual: true))
        })
    }

    /// Positions of manually reordered items inside one category, evenly spread in the given
    /// order and merged into the store's existing positions (other categories' items keep theirs).
    public static func manualItemPositions(for order: [String], mergingInto positions: [String: OrderPosition]) -> [String: OrderPosition] {
        let denominator = Double(max(order.count - 1, 1))
        var result = positions
        for (index, key) in order.enumerated() {
            result[key] = OrderPosition(value: Double(index) / denominator, samples: 1, isManual: true)
        }
        return result
    }
}
