import Foundation
import MarqetCore

/// Category sections inside the cards (KONZEPT §6.3) and their order (§6.4).
extension AppModel {
    func category(of item: ShoppingItem) -> ItemCategory {
        classifier.classify(item.title).category
    }

    /// Sections of a card. Grocery stores get category sections in walking order; everything
    /// else is one flat list. Learned item order only with Pro route learning.
    func sections(for page: PageID, items pageItems: [ShoppingItem]) -> [CardSection] {
        _ = orderRevision
        let store = page.storeID.flatMap(store(_:))
        let usesLearning = isPro && routeLearningEnabled
        // A manual drag (Free or Pro) always counts. Learned positions only with route learning –
        // without it, items nobody dragged stay alphabetical.
        let loaded = store.map { itemPositionsLoaded(for: $0.id) } ?? [:]
        let itemPositions = usesLearning ? loaded : loaded.filter(\.value.isManual)
        let ordering = SectionBuilder.Ordering(
            categoryPositions: store.map { categoryPositionsLoaded(for: $0.id) } ?? [:],
            itemPositions: itemPositions.isEmpty && !usesLearning ? nil : itemPositions
        )
        // Unsorted and non-grocery cards stay flat and keep insertion order (newest last).
        return SectionBuilder.sections(
            items: pageItems,
            storeType: store?.type,
            category: category(of:),
            ordering: ordering
        )
    }

    /// Category order of a store, as shown in "Abschnitte sortieren".
    func categoryOrder(for storeID: Store.ID) -> [ItemCategory] {
        _ = orderRevision
        return SectionBuilder.categoryOrder(categoryPositionsLoaded(for: storeID))
    }

    /// Manual section order (Free and Pro). Route learning keeps refining it afterwards (Pro).
    func setCategoryOrder(_ order: [ItemCategory], for storeID: Store.ID) {
        let positions = RouteLearner.manualPositions(for: order)
        categoryPositions[storeID] = positions
        orderRevision += 1
        do {
            try learning.saveCategoryPositions(positions, storeID: storeID)
        } catch {
            present(error)
        }
    }

    /// Manual order of items inside one category (Free and Pro). Route learning (Pro) keeps
    /// refining it afterwards; a manual position moves half as fast under new learning data.
    func setItemOrder(_ items: [ShoppingItem], for storeID: Store.ID) {
        let keys = items.map { ItemKeyNormalizer.matchingKey(for: $0.title) }
        let positions = RouteLearner.manualItemPositions(for: keys, mergingInto: itemPositionsLoaded(for: storeID))
        itemPositions[storeID] = positions
        orderRevision += 1
        do {
            try learning.saveItemPositions(positions, storeID: storeID)
        } catch {
            present(error)
        }
    }

    /// Drag inside a store card (KONZEPT #55): `moved` now belongs to the section of `category`
    /// in `order`. Landing in another category section is a correction, like "Kategorie ändern".
    /// Items of other stores are ignored – they come over through the card's own drop target.
    func arrangeItem(_ moved: ShoppingItem, into category: ItemCategory?, order: [ShoppingItem], in storeID: Store.ID) {
        guard moved.storeID == storeID, !moved.isCompleted else { return }
        if let category, self.category(of: moved) != category {
            setCategory(category, for: moved)
        }
        setItemOrder(order, for: storeID)
    }

    /// "Kategorie ändern": a correction that wins over dictionary and AI from now on.
    func setCategory(_ category: ItemCategory, for item: ShoppingItem) {
        let key = ItemKeyNormalizer.matchingKey(for: item.title)
        classifier.learned[key] = (category, true)
        do {
            try learning.setCategory(category, for: key, isUserCorrection: true)
        } catch {
            present(error)
        }
    }

    /// Learned without correction (Apple Intelligence), never overrides a correction.
    func learnCategory(_ category: ItemCategory, forKey key: String) {
        if classifier.learned[key]?.isCorrection == true { return }
        classifier.learned[key] = (category, false)
        do {
            try learning.setCategory(category, for: key, isUserCorrection: false)
        } catch {
            present(error)
        }
    }

    func categoryPositionsLoaded(for storeID: Store.ID) -> [ItemCategory: OrderPosition] {
        if let cached = categoryPositions[storeID] { return cached }
        let loaded = (try? learning.categoryPositions(storeID: storeID)) ?? [:]
        categoryPositions[storeID] = loaded
        return loaded
    }

    func itemPositionsLoaded(for storeID: Store.ID) -> [String: OrderPosition] {
        if let cached = itemPositions[storeID] { return cached }
        let loaded = (try? learning.itemPositions(storeID: storeID)) ?? [:]
        itemPositions[storeID] = loaded
        return loaded
    }
}
