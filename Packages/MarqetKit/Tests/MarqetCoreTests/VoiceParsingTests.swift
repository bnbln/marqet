import Foundation
@testable import MarqetCore
import Testing

@Suite("Voice: rules and draft")
struct VoiceParsingTests {
    let lexicon = SpokenStoreLexicon(stores: [
        (name: "Markt", spellings: ["Wochenmarkt", "Bauernmarkt"]),
        (name: "Rewe", spellings: []),
        (name: "Aldi Süd", spellings: ["Aldi"]),
        (name: "dm", spellings: ["dm-drogerie markt"]),
    ])

    @Test func userExampleWithPunctuation() {
        let transcript = """
            Ich brauche 10 Eier und will sie auf dem Markt kaufen, genau wie Suppengrün und 500 g Kartoffeln \
            mehligkochend. Bei Rewe will ich 500 g Hackfleisch kaufen. Ah, und ich brauche Zwiebeln vom Markt.
            """
        let entries = VoiceRuleParser.parse(transcript, lexicon: lexicon)
        #expect(entries == [
            SpokenEntry(name: "Eier", quantity: "10", storeName: "Markt"),
            SpokenEntry(name: "Suppengrün", storeName: "Markt"),
            SpokenEntry(name: "Kartoffeln mehligkochend", quantity: "500 g", storeName: "Markt"),
            SpokenEntry(name: "Hackfleisch", quantity: "500 g", storeName: "Rewe"),
            SpokenEntry(name: "Zwiebeln", storeName: "Markt"),
        ])
    }

    @Test func compactUnitsAndNumberWords() {
        let entries = VoiceRuleParser.parse("zwei Liter Milch, 500g Mehl und ein Kilo Äpfel bei Aldi", lexicon: lexicon)
        #expect(entries.map(\.title) == ["2 l Milch", "500 g Mehl", "1 kg Äpfel"])
        #expect(entries.allSatisfy { $0.storeName == "Aldi Süd" })
    }

    @Test func containerUnits() {
        let entries = VoiceRuleParser.parse(
            "eine Dose Tomaten, 1 Tafel Schokolade, zwei Packungen Nudeln, ein Dutzend Eier und ein paar Äpfel",
            lexicon: lexicon
        )
        #expect(entries.map(\.title) == ["1 Dose Tomaten", "1 Tafel Schokolade", "2 Packungen Nudeln", "12 Eier", "Äpfel"])
    }

    @Test func englishContainerUnits() {
        let entries = VoiceRuleParser.parse("two cans of tomatoes, two bars of chocolate", lexicon: lexicon)
        #expect(entries.map(\.title) == ["2 cans Tomatoes", "2 bars Chocolate"])
    }

    @Test func articleIsNoQuantity() {
        let entries = VoiceRuleParser.parse("Eine Gurke und einen Brokkoli", lexicon: lexicon)
        #expect(entries == [SpokenEntry(name: "Gurke"), SpokenEntry(name: "Brokkoli")])
    }

    @Test func trailingQuantity() {
        let entries = VoiceRuleParser.parse("Hackfleisch 500 Gramm vom Wochenmarkt", lexicon: lexicon)
        #expect(entries == [SpokenEntry(name: "Hackfleisch", quantity: "500 g", storeName: "Markt")])
    }

    @Test func continuationCarriesStoreAcrossSentences() {
        let entries = VoiceRuleParser.parse("Bei Rewe Milch. Genau wie Butter. Brot. Ich brauche noch Salz.", lexicon: lexicon)
        #expect(entries.map(\.storeName) == ["Rewe", "Rewe", "Rewe", nil])
    }

    @Test func hyphenatedNamesStayTogether() {
        let entries = VoiceRuleParser.parse("Bio-Milch und Zahnpasta vom dm", lexicon: lexicon)
        #expect(entries.map(\.name) == ["Bio-Milch", "Zahnpasta"])
        #expect(entries.allSatisfy { $0.storeName == "dm" })
    }

    @Test func lowercaseClauseDescribesThePreviousItem() {
        let entries = VoiceRuleParser.parse("500 g Kartoffeln, mehligkochend, und Zwiebeln vom Markt.", lexicon: lexicon)
        #expect(entries == [
            SpokenEntry(name: "Kartoffeln, mehligkochend", quantity: "500 g", storeName: "Markt"),
            SpokenEntry(name: "Zwiebeln", storeName: "Markt"),
        ])
        // Same identity as the language model's spelling – the row stays in place.
        #expect(entries[0].identityKey == SpokenEntry(name: "Kartoffeln (mehligkochend)").identityKey)
    }

    @Test func storeOnlyClauseAddsNothing() {
        #expect(VoiceRuleParser.parse("Ich gehe nachher zu Rewe.", lexicon: lexicon).isEmpty)
    }

    // MARK: Stores across sentences

    @Test func storeOnlySentenceRefersBack() {
        let entries = VoiceRuleParser.parse("Ich brauche Milch und Butter. Die hole ich bei Rewe. Und Brot.", lexicon: lexicon)
        #expect(entries.map(\.storeName) == ["Rewe", "Rewe", "Rewe"])
    }

    @Test func transcriberPeriodInsideOneThought() {
        // The transcriber ends the sentence at a pause, the store follows in the next one.
        let entries = VoiceRuleParser.parse("Ich brauche 10 Eier. Und will sie auf dem Markt kaufen.", lexicon: lexicon)
        #expect(entries == [SpokenEntry(name: "Eier", quantity: "10", storeName: "Markt")])
    }

    @Test func announcedStoreAppliesToFollowingSentences() {
        let entries = VoiceRuleParser.parse("Bei Rewe brauche ich einiges. Milch, Butter und Käse. Außerdem Brot.", lexicon: lexicon)
        #expect(entries.map(\.name) == ["Milch", "Butter", "Käse", "Brot"])
        #expect(entries.allSatisfy { $0.storeName == "Rewe" })
    }

    @Test func colonIntroducesAList() {
        let entries = VoiceRuleParser.parse("Rewe: Milch, Butter. Markt: Eier", lexicon: lexicon)
        #expect(entries.map(\.storeName) == ["Rewe", "Rewe", "Markt"])
    }

    @Test func bareEnumerationContinuesButNewThoughtDoesNot() {
        let entries = VoiceRuleParser.parse("Bei Rewe Milch. Butter. Ich brauche noch Zahnpasta.", lexicon: lexicon)
        #expect(entries.map(\.storeName) == ["Rewe", "Rewe", nil])
    }

    @Test func storeSuffixIsPartOfTheStore() {
        let entries = VoiceRuleParser.parse("Hackfleisch vom Rewe-Markt", lexicon: lexicon)
        #expect(entries == [SpokenEntry(name: "Hackfleisch", storeName: "Rewe")])
    }

    // MARK: Missing commas

    @Test func dictationWithoutCommas() {
        // As transcribed on device: the commas between the items are missing.
        let transcript = "Ich möchte Brot auf dem Markt kaufen Klopapier bei Rewe. Milch, Butter Zwiebeln bei Rewe."
        let entries = VoiceRuleParser.parse(transcript, lexicon: lexicon)
        #expect(entries == [
            SpokenEntry(name: "Brot", storeName: "Markt"),
            SpokenEntry(name: "Klopapier", storeName: "Rewe"),
            SpokenEntry(name: "Milch", storeName: "Rewe"),
            SpokenEntry(name: "Butter", storeName: "Rewe"),
            SpokenEntry(name: "Zwiebeln", storeName: "Rewe"),
        ])
    }

    @Test func storeFirstClausesSplitBeforeEachStore() {
        let entries = VoiceRuleParser.parse("Bei Rewe Milch bei Aldi Butter", lexicon: lexicon)
        #expect(entries == [SpokenEntry(name: "Milch", storeName: "Rewe"), SpokenEntry(name: "Butter", storeName: "Aldi Süd")])
    }

    @Test func knownPhrasesAndAdjectivesStayTogether() {
        let entries = VoiceRuleParser.parse("Rote Bete, frische Milch, Kinder Riegel und 500 g Butter Zwiebeln", lexicon: lexicon)
        #expect(entries.map(\.title) == ["Rote Bete", "Frische Milch", "Kinder Riegel", "500 g Butter", "Zwiebeln"])
    }

    // MARK: Pauses

    @Test func pauseKeepsLaterStoreWithItsOwnItem() {
        // "Brötchen [Pause] HDMI-Kabel beim Mediamarkt": the pause becomes a period.
        let lexicon = SpokenStoreLexicon(stores: [(name: "MediaMarkt", spellings: ["Media Markt"])])
        let entries = VoiceRuleParser.parse("Brötchen. HDMI-Kabel beim Mediamarkt.", lexicon: lexicon)
        #expect(entries == [
            SpokenEntry(name: "Brötchen"),
            SpokenEntry(name: "HDMI-Kabel", storeName: "MediaMarkt"),
        ])
    }

    @Test func storeAfterItsItemBindsOnlyToIt() {
        // "Brötchen, HDMI-Kabel von Mediamarkt, Kuchen, Milch, Butter" – only the cable goes to Mediamarkt.
        let lexicon = SpokenStoreLexicon(stores: [(name: "MediaMarkt", spellings: ["Media Markt"]), (name: "Rewe", spellings: [])])
        let expected = [
            SpokenEntry(name: "Brötchen"),
            SpokenEntry(name: "HDMI-Kabel", storeName: "MediaMarkt"),
            SpokenEntry(name: "Kuchen"),
            SpokenEntry(name: "Milch"),
            SpokenEntry(name: "Butter"),
        ]
        #expect(VoiceRuleParser.parse("Brötchen, HDMI-Kabel von Mediamarkt, Kuchen, Milch, Butter.", lexicon: lexicon) == expected)
        // The same with a pause after every item.
        #expect(VoiceRuleParser.parse("Brötchen. HDMI-Kabel von Mediamarkt. Kuchen. Milch, Butter.", lexicon: lexicon) == expected)
    }

    @Test func announcedStoreStillCoversTheEnumeration() {
        let entries = VoiceRuleParser.parse("Bei Rewe Milch, Butter. Eier.", lexicon: lexicon)
        #expect(entries.map(\.storeName) == ["Rewe", "Rewe", "Rewe"])
    }

    @Test func explicitContinuationFollowsATrailingStore() {
        let entries = VoiceRuleParser.parse("Eier vom Markt. Und Butter. Ich brauche noch Salz, Zucker vom Markt, Mehl.", lexicon: lexicon)
        #expect(entries.map(\.storeName) == ["Markt", "Markt", nil, "Markt", nil])
    }

    @Test func hyphenatedCompoundEndsAnEnumerationWithoutCommas() {
        let entries = VoiceRuleParser.parse("Brötchen HDMI-Kabel", lexicon: lexicon)
        #expect(entries.map(\.name) == ["Brötchen", "HDMI-Kabel"])
    }

    @Test func pauseBetweenWordsEndsTheSentence() {
        let runs = [
            TimedText("Brötchen", start: 0.2, end: 0.8),
            TimedText(" "),
            TimedText("HDMI", start: 2.1, end: 2.4),
            TimedText("-"),
            TimedText("Kabel", start: 2.4, end: 2.8),
            TimedText(" "),
            TimedText("beim", start: 2.9, end: 3.1),
            TimedText(" "),
            TimedText("Mediamarkt", start: 3.1, end: 3.7),
        ]
        let marked = PauseMarker.mark(runs, after: nil)
        #expect(marked.text == "Brötchen. HDMI-Kabel beim Mediamarkt")
        #expect(!marked.startsAfterPause)
        #expect(marked.lastEnd == 3.7)
    }

    @Test func pauseTurnsACommaIntoAPeriod() {
        let runs = [TimedText("Brötchen,", start: 0, end: 0.6), TimedText(" HDMI-Kabel", start: 1.8, end: 2.5)]
        #expect(PauseMarker.mark(runs, after: nil).text == "Brötchen. HDMI-Kabel")
    }

    @Test func quickEnumerationHasNoPause() {
        let runs = [
            TimedText("Milch", start: 0, end: 0.4), TimedText(" "),
            TimedText("Butter", start: 0.7, end: 1.1), TimedText(" "),
            TimedText("Eier", start: 1.4, end: 1.7),
        ]
        #expect(PauseMarker.mark(runs, after: nil).text == "Milch Butter Eier")
    }

    @Test func pauseBeforeANewResult() {
        let marked = PauseMarker.mark([TimedText("HDMI-Kabel", start: 3, end: 3.6)], after: 1.2)
        #expect(marked.startsAfterPause)
        #expect(PauseMarker.join(PauseMarker.endingSentence("Brötchen"), marked.text) == "Brötchen. HDMI-Kabel")
        #expect(PauseMarker.endingSentence("Brötchen. ") == "Brötchen.")
    }

    // MARK: English

    @Test func englishDictation() {
        let transcript = """
            I need a dozen eggs from the market, as well as two pounds of potatoes.             At Rewe I want 500 grams of ground beef. Oh, and onions from the farmers market.
            """
        let english = SpokenStoreLexicon(stores: [(name: "Markt", spellings: ["Market", "Farmers market"]), (name: "Rewe", spellings: [])])
        let entries = VoiceRuleParser.parse(transcript, lexicon: english, language: .english)
        #expect(entries == [
            SpokenEntry(name: "Eggs", quantity: "12", storeName: "Markt"),
            SpokenEntry(name: "Potatoes", quantity: "2 lb", storeName: "Markt"),
            SpokenEntry(name: "Ground beef", quantity: "500 g", storeName: "Rewe"),
            SpokenEntry(name: "Onions", storeName: "Markt"),
        ])
    }

    @Test func englishStoreInNextSentenceAndArticles() {
        let entries = VoiceRuleParser.parse("I need an onion and 2 cans of tomatoes. Get them at Aldi.", lexicon: lexicon, language: .english)
        #expect(entries == [
            SpokenEntry(name: "Onion", storeName: "Aldi Süd"),
            SpokenEntry(name: "Tomatoes", quantity: "2 cans", storeName: "Aldi Süd"),
        ])
    }

    @Test func englishLowercaseIsNoAttribute() {
        let entries = VoiceRuleParser.parse("milk, butter at rewe", lexicon: lexicon, language: .english)
        #expect(entries.map(\.name) == ["Milk", "Butter"])
    }

    @Test func lastStoreMention() {
        #expect(VoiceRuleParser.lastStoreMention(in: "Eier vom Markt, bei Rewe Hack", lexicon: lexicon) == "Rewe")
        #expect(VoiceRuleParser.lastStoreMention(in: "Eier und Milch", lexicon: lexicon) == nil)
    }

    // MARK: Draft

    @Test func draftKeepsIdentityWhenModelRefines() {
        var draft = VoiceDraft()
        draft.merge([SpokenEntry(name: "Kartoffeln mehligkochend", quantity: "500 g")], origin: .rules, transcriptLength: 40, isComplete: true)
        let id = draft.entries[0].id
        draft.merge([SpokenEntry(name: "Kartoffeln, mehligkochend", quantity: "500 g", storeName: "Markt")], origin: .model, transcriptLength: 40, isComplete: true)
        #expect(draft.entries.count == 1)
        #expect(draft.entries[0].id == id)
        #expect(draft.entries[0].spoken.storeName == "Markt")
        #expect(draft.entries[0].origin == .model)
    }

    @Test func modelPassKeepsEntriesHeardLater() {
        var draft = VoiceDraft()
        draft.merge([SpokenEntry(name: "Eier")], origin: .rules, transcriptLength: 10, isComplete: true)
        draft.merge([SpokenEntry(name: "Eier"), SpokenEntry(name: "Milch")], origin: .rules, transcriptLength: 30, isComplete: true)
        // The model only read the first 10 characters.
        draft.merge([SpokenEntry(name: "Eier", storeName: "Markt")], origin: .model, transcriptLength: 10, isComplete: true)
        #expect(draft.entries.map(\.spoken.name) == ["Eier", "Milch"])
    }

    @Test func rulesDoNotRemoveModelEntries() {
        var draft = VoiceDraft()
        draft.merge([SpokenEntry(name: "Zwiebeln", quantity: "1 kg", storeName: "Markt")], origin: .model, transcriptLength: 20, isComplete: true)
        draft.merge([SpokenEntry(name: "Zwiebeln")], origin: .rules, transcriptLength: 25, isComplete: true)
        draft.merge([], origin: .rules, transcriptLength: 25, isComplete: true)
        #expect(draft.entries.map(\.spoken) == [SpokenEntry(name: "Zwiebeln", quantity: "1 kg", storeName: "Markt")])
    }

    @Test func spokenStoreBeatsModelGuess() {
        var draft = VoiceDraft()
        draft.merge([SpokenEntry(name: "Kartoffeln", storeName: "Markt"), SpokenEntry(name: "Brot")], origin: .rules, transcriptLength: 30, isComplete: true)
        draft.merge([SpokenEntry(name: "Kartoffeln", storeName: "Rewe"), SpokenEntry(name: "Brot", storeName: "Rewe")], origin: .model, transcriptLength: 30, isComplete: true)
        // The model fills the gap (Brot), but does not move what was said explicitly.
        #expect(draft.entries.map(\.spoken.storeName) == ["Markt", "Rewe"])
    }

    @Test func userChoicesSurviveCorrections() {
        var draft = VoiceDraft()
        draft.merge([SpokenEntry(name: "Milch"), SpokenEntry(name: "Brot")], origin: .model, transcriptLength: 20, isComplete: true)
        draft.move("milch", to: .inbox)
        draft.merge([], origin: .model, transcriptLength: 20, isComplete: true)
        #expect(draft.entries.map(\.id) == ["milch"])
    }

    @Test func gluedItemsDisappearWhenTheyAreHeardApart() {
        var draft = VoiceDraft()
        // An early pass (here the model on a volatile transcript) heard "Milchbutter".
        draft.merge([SpokenEntry(name: "Kuchen"), SpokenEntry(name: "Milchbutter")], origin: .model, transcriptLength: 20, isComplete: true)
        draft.merge([SpokenEntry(name: "Kuchen"), SpokenEntry(name: "Milch"), SpokenEntry(name: "Butter")], origin: .rules, transcriptLength: 26, isComplete: true)
        #expect(draft.entries.map(\.id) == ["kuchen", "milch", "butter"])
    }

    @Test func concatenation() {
        #expect(VoiceDraft.isConcatenation("milchbutter", of: ["kuchen", "milch", "butter"]))
        #expect(!VoiceDraft.isConcatenation("milch", of: ["milch", "butter"]))
        #expect(!VoiceDraft.isConcatenation("kuchenbutter", of: ["kuchen", "milch", "butter"]))
    }

    @Test func duplicatesGetOwnRows() {
        var draft = VoiceDraft()
        draft.merge([SpokenEntry(name: "Milch", storeName: "Rewe"), SpokenEntry(name: "Milch", storeName: "Aldi Süd")], origin: .rules, transcriptLength: 20, isComplete: true)
        #expect(draft.entries.map(\.id) == ["milch", "milch#1"])
    }
}
