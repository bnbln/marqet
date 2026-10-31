import Foundation

/// The items recognized so far in one dictation, with stable identities (KONZEPT §3.3).
///
/// Rules and the language model each deliver complete lists; `merge` folds them into the draft
/// so rows keep their identity (and their animation) while a store or quantity is corrected,
/// and edits by the user always win over later parser passes.
public struct VoiceDraft: Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        /// Found by `VoiceRuleParser` – shown right away, may still change.
        case rules
        /// Confirmed or found by the language model.
        case model
    }

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String
        public var spoken: SpokenEntry
        public var origin: Origin
        public var isSelected = true
        /// Store picked by the user in review; parser passes no longer touch the store.
        public var storeOverride: StoreChoice?
        /// Store the rules heard in the entry's own sentence ("bei Rewe …"). An explicit mention
        /// beats the model's reading: the small on-device model sometimes drifts to a store of a
        /// neighboring sentence, the rules never do.
        public var spokenStoreName: String?
        /// Transcript length when the entry was first heard – a model pass over a shorter
        /// transcript must not remove it.
        public var heardAt: Int
    }

    /// A store picked by the user: one of theirs, a catalog chain not added yet, or the inbox.
    public enum StoreChoice: Hashable, Sendable {
        case store(Store.ID)
        case catalog(String)
        case inbox
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public var selectedCount: Int { entries.filter(\.isSelected).count }

    /// Folds one parser pass into the draft.
    ///
    /// - Parameters:
    ///   - parsed: the complete list of that pass, in spoken order.
    ///   - origin: `.model` marks matched entries as confirmed.
    ///   - transcriptLength: length of the transcript the pass read.
    ///   - isComplete: a complete pass removes entries it no longer contains (a correction like
    ///     "doch keine Milch"), except those heard after its transcript or touched by the user.
    public mutating func merge(_ parsed: [SpokenEntry], origin: Origin, transcriptLength: Int, isComplete: Bool) {
        var seenIDs = Set<String>()
        var seenKeys: [String] = []
        var occurrences: [String: Int] = [:]
        for spoken in parsed {
            let key = spoken.identityKey
            guard !key.isEmpty else { continue }
            seenKeys.append(key)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            let id = occurrence == 0 ? key : "\(key)#\(occurrence)"
            seenIDs.insert(id)
            if let index = entries.firstIndex(where: { $0.id == id }) {
                // Rules must not undo what the model already decided – except the store they heard.
                if origin == .rules, entries[index].origin == .model {
                    if let store = spoken.storeName {
                        entries[index].spokenStoreName = store
                        entries[index].spoken.storeName = store
                    }
                    continue
                }
                if origin == .rules { entries[index].spokenStoreName = spoken.storeName }
                entries[index].spoken.name = spoken.name
                entries[index].spoken.quantity = spoken.quantity ?? entries[index].spoken.quantity
                entries[index].spoken.storeName = entries[index].spokenStoreName ?? spoken.storeName
                entries[index].origin = origin
            } else {
                var entry = Entry(id: id, spoken: spoken, origin: origin, heardAt: transcriptLength)
                if origin == .rules { entry.spokenStoreName = spoken.storeName }
                entries.append(entry)
            }
        }
        // "Milchbutter" from a pass that heard "Milch Butter" as one item, while this pass reads
        // "Milch" and "Butter": the merged row is the same words twice, whoever found it.
        entries.removeAll { entry in
            !seenIDs.contains(entry.id)
                && entry.storeOverride == nil
                && entry.isSelected
                && Self.isConcatenation(Self.baseKey(of: entry.id), of: seenKeys)
        }
        guard isComplete else { return }
        entries.removeAll { entry in
            !seenIDs.contains(entry.id)
                && entry.storeOverride == nil
                && entry.isSelected
                && entry.heardAt <= transcriptLength
                // Rules only drop their own guesses; model-confirmed rows need the model to go.
                && (origin == .model || entry.origin == .rules)
        }
    }

    /// "milch#1" → "milch".
    private static func baseKey(of id: String) -> String {
        id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id
    }

    /// `key` is two or more neighboring keys of `keys` written together ("milch" + "butter").
    public static func isConcatenation(_ key: String, of keys: [String]) -> Bool {
        for start in keys.indices {
            var joined = keys[start]
            for next in keys.indices[(start + 1)...] {
                joined += keys[next]
                if joined == key { return true }
                if joined.count >= key.count { break }
            }
        }
        return false
    }

    public mutating func toggle(_ id: Entry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isSelected.toggle()
    }

    public mutating func move(_ id: Entry.ID, to choice: StoreChoice) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].storeOverride = choice
        entries[index].isSelected = true
    }

    public mutating func remove(_ id: Entry.ID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        entries = []
    }
}
