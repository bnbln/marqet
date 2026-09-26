import Foundation

/// Grocery categories, modelled after Apple Reminders' grocery sections (KONZEPT §6.3).
/// The declaration order is the default walking order of a typical German supermarket.
public enum ItemCategory: String, CaseIterable, Codable, Sendable {
    case produce
    case bakery
    case dairyEggs
    case cheese
    case meat
    case fish
    case breakfast
    case pantry
    case baking
    case snacks
    case frozen
    case beverages
    case alcohol
    case personalCare
    case household
    case baby
    case pet
    case other
}
