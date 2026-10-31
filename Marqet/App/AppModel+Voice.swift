import Foundation
import MarqetCore

/// Opens the dictation screen (KONZEPT §3.1).
struct VoiceRequest: Identifiable, Equatable {
    let id = UUID()
    /// Where items go that name no store: the card the user came from (composer on a store),
    /// otherwise `nil` – then memory decides, and the inbox catches the rest.
    var defaultPage: PageID?
}

/// A store the dictation can name: one of the user's stores or a catalog chain not added yet.
struct VoiceStoreOption: Identifiable, Hashable {
    let choice: VoiceDraft.StoreChoice
    /// Store for badge and colors. For catalog chains a preview that is only created on commit.
    let store: Store
    let spellings: [String]
    var isNew: Bool { if case .catalog = choice { true } else { false } }
    var id: VoiceDraft.StoreChoice { choice }
    var name: String { store.name }
}

/// Where one entry of the draft lands and why.
struct VoicePlacement: Hashable {
    enum Reason: Hashable {
        /// Named in the dictation.
        case spoken
        /// Chosen by the user in review.
        case picked
        /// The card the dictation started from.
        case context
        /// Learned from earlier assignments.
        case memory
        /// No store known: inbox.
        case none
    }

    let choice: VoiceDraft.StoreChoice
    let reason: Reason
}

extension AppModel {
    func startVoice(defaultPage: PageID? = nil) {
        endComposer()
        dismissBriefing()
        voiceRequest = VoiceRequest(defaultPage: defaultPage?.storeID != nil ? defaultPage : nil)
    }

    /// The user's stores first (they win over a chain with the same spoken name), then the
    /// catalog chains of the region. Short forms ("Aldi" for "Aldi Süd") only when unique.
    func voiceStoreOptions() -> [VoiceStoreOption] {
        let own = sortedStores
        let firstWords = own.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        var options = own.enumerated().map { index, store in
            let short = firstWords[index]
            let isUnique = short != store.name && firstWords.filter { $0 == short }.count == 1
            return VoiceStoreOption(
                choice: .store(store.id),
                store: store,
                spellings: store.aliases + (isUnique ? [short] : [])
            )
        }
        for entry in catalogSuggestions {
            var preview = entry.makeStore(sortIndex: nextSortIndex)
            preview.plannedAt = .now
            options.append(VoiceStoreOption(choice: .catalog(entry.key), store: preview, spellings: entry.aliases))
        }
        return options
    }

    func voiceLexicon(for options: [VoiceStoreOption]) -> SpokenStoreLexicon {
        SpokenStoreLexicon(stores: options.map { ($0.name, $0.spellings) })
    }

    /// Store names and spellings for the speech recognizer's vocabulary.
    func voiceContextualStrings(for options: [VoiceStoreOption]) -> [String] {
        Array(options.flatMap { [$0.name] + $0.spellings }.uniqued().prefix(100))
    }

    func placement(of entry: VoiceDraft.Entry, options: [VoiceStoreOption], defaultPage: PageID?) -> VoicePlacement {
        if let override = entry.storeOverride { return VoicePlacement(choice: override, reason: .picked) }
        if let name = entry.spoken.storeName,
           let option = options.first(where: { ItemKeyNormalizer.storeNameKey($0.name) == ItemKeyNormalizer.storeNameKey(name) }) {
            return VoicePlacement(choice: option.choice, reason: .spoken)
        }
        if let id = defaultPage?.storeID, store(id) != nil {
            return VoicePlacement(choice: .store(id), reason: .context)
        }
        let valid = Set(stores.map(\.id))
        if let suggestion = SuggestionEngine.suggestion(for: entry.spoken.name, memory: assignmentMemory, validStores: valid) {
            return VoicePlacement(choice: .store(suggestion.storeID), reason: .memory)
        }
        return VoicePlacement(choice: .inbox, reason: .none)
    }

    /// Adds the selected entries: catalog chains become planned stores, everything else lands
    /// on its card. One undo step for the whole dictation. Returns the number of new items.
    @discardableResult
    func commitVoiceDraft(_ draft: VoiceDraft, options: [VoiceStoreOption], defaultPage: PageID?) async -> Int {
        var createdStores: [String: Store.ID] = [:]
        var entries: [(title: String, page: PageID)] = []
        for entry in draft.entries where entry.isSelected {
            let page: PageID
            switch placement(of: entry, options: options, defaultPage: defaultPage).choice {
            case .store(let id):
                pin(id)
                page = .store(id)
            case .catalog(let key):
                if let id = createdStores[key] {
                    page = .store(id)
                } else if let catalogEntry = catalog?.entry(forKey: key) {
                    let store = addStore(from: catalogEntry, planned: true)
                    createdStores[key] = store.id
                    page = .store(store.id)
                } else {
                    page = .unsorted
                }
            case .inbox:
                page = .unsorted
            }
            entries.append((entry.spoken.title, page))
        }
        let created = await addItems(entries)
        if let first = entries.first?.page {
            activePage = first
            pageRequest = first
        }
        return created.count
    }

    /// Apple Intelligence reads the dictation (Pro). Free and devices without it keep the rules.
    var interpretsDictationWithIntelligence: Bool {
        isPro && intelligenceEnabled && intelligence.isAvailable
    }
}
