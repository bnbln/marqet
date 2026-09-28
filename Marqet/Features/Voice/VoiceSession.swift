import Foundation
import MarqetCore
import Observation

/// One dictation from the first word to "Hinzufügen" (KONZEPT §3.3).
///
/// Two readers work on the transcript: `VoiceRuleParser` on every change (instant, rows appear
/// while speaking) and – with Pro and Apple Intelligence – the language model after each
/// finalized phrase and after short pauses. Both feed `VoiceDraft`, which keeps row identities
/// stable, so a corrected store moves the row instead of replacing it.
@MainActor
@Observable
final class VoiceSession {
    enum Phase: Equatable {
        /// Microphone permission, speech model download (`progress` 0…1 while downloading).
        case preparing(progress: Double?)
        case listening
        /// Last words are finalized, the model reads the whole dictation once more.
        case finishing
        /// "Hinzufügen?" with the entries per list.
        case review
        case failed(String, canOpenSettings: Bool)
    }

    /// Entries of one target card, in the order the stores were first mentioned.
    struct Group: Identifiable, Equatable {
        let choice: VoiceDraft.StoreChoice
        let option: VoiceStoreOption?
        var rows: [Row]
        var id: VoiceDraft.StoreChoice { choice }
    }

    struct Row: Identifiable, Equatable {
        let entry: VoiceDraft.Entry
        let placement: VoicePlacement
        var id: String { entry.id }
    }

    private(set) var phase: Phase = .preparing(progress: nil)
    private(set) var transcript = LiveTranscriber.Transcript()
    private(set) var draft = VoiceDraft()
    /// Microphone level 0…1, smoothed.
    private(set) var level: Float = 0
    /// Store the user talked about last; its card is highlighted.
    private(set) var activeChoice: VoiceDraft.StoreChoice?
    /// Apple Intelligence is reading the dictation right now.
    private(set) var isInterpreting = false

    let options: [VoiceStoreOption]
    let defaultPage: PageID?
    let usesIntelligence: Bool
    /// The app's language (German or English) – for the recognizer, the rules and the model.
    let language: VoiceLanguage
    @ObservationIgnored private let locale: Locale

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let lexicon: SpokenStoreLexicon
    @ObservationIgnored private var transcriber = LiveTranscriber()
    @ObservationIgnored private var modelPass: Task<Void, Never>?
    @ObservationIgnored private var modelDebounce: Task<Void, Never>?
    @ObservationIgnored private var interpretedLength = 0
    @ObservationIgnored private var demo: Task<Void, Never>?

    init(model: AppModel, request: VoiceRequest) {
        self.model = model
        options = model.voiceStoreOptions()
        lexicon = model.voiceLexicon(for: options)
        defaultPage = request.defaultPage
        usesIntelligence = model.interpretsDictationWithIntelligence
        let appLanguage = Bundle.main.preferredLocalizations.first ?? "de"
        language = VoiceLanguage(languageCode: appLanguage)
        // Keep the user's region ("en-GB", "de-AT") when it matches the app's language.
        locale = Locale.preferredLanguages.lazy.map(Locale.init(identifier:))
            .first { $0.language.languageCode?.identifier == appLanguage }
            ?? Locale(identifier: language == .english ? "en-US" : "de-DE")
    }

    // MARK: Lifecycle

    func start() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo-voice") {
            playDemo()
            return
        }
        #endif
        phase = .preparing(progress: nil)
        guard await LiveTranscriber.requestMicrophone() else {
            fail(LiveTranscriber.Failure.microphoneDenied, canOpenSettings: true)
            return
        }
        do {
            try await transcriber.prepare(locale: locale) { [weak self] progress in
                self?.phase = .preparing(progress: progress)
            }
            try await listen()
        } catch {
            fail(error, canOpenSettings: false)
        }
    }

    /// "Weitersprechen": keeps the draft and listens again.
    func resume() async {
        guard phase == .review else { return }
        // Carry the transcript forward while giving this recording segment fresh audio resources.
        phase = .preparing(progress: nil)
        transcriber = LiveTranscriber(transcript: transcript)
        do {
            try await transcriber.prepare(locale: locale) { [weak self] progress in
                self?.phase = .preparing(progress: progress)
            }
            try await listen()
        } catch {
            fail(error, canOpenSettings: false)
        }
    }

    /// Stop button: finalize, read everything once more, then ask.
    func stop() async {
        guard phase == .listening else { return }
        phase = .finishing
        level = 0
        demo?.cancel()
        await transcriber.finish()
        applyRules()
        modelDebounce?.cancel()
        if usesIntelligence {
            modelPass?.cancel()
            await interpret(transcript.full)
        }
        activeChoice = nil
        phase = .review
    }

    func cancel() async {
        demo?.cancel()
        modelDebounce?.cancel()
        modelPass?.cancel()
        await transcriber.cancel()
    }

    /// Adds the selected entries to the lists. Returns the number of new items.
    func commit() async -> Int {
        await model.commitVoiceDraft(draft, options: options, defaultPage: defaultPage)
    }

    private func listen() async throws {
        transcriber.onTranscript = { [weak self] transcript in self?.receive(transcript) }
        transcriber.onLevel = { [weak self] level in self?.receive(level: level) }
        try await transcriber.start(contextualStrings: model.voiceContextualStrings(for: options))
        phase = .listening
    }

    private func fail(_ error: any Error, canOpenSettings: Bool) {
        phase = .failed(error.localizedDescription, canOpenSettings: canOpenSettings)
    }

    // MARK: Review edits

    func toggle(_ row: Row) {
        draft.toggle(row.id)
    }

    func move(_ row: Row, to choice: VoiceDraft.StoreChoice) {
        draft.move(row.id, to: choice)
    }

    func remove(_ row: Row) {
        draft.remove(row.id)
    }

    // MARK: Groups

    var groups: [Group] {
        var groups: [Group] = []
        for entry in draft.entries {
            let placement = model.placement(of: entry, options: options, defaultPage: defaultPage)
            let row = Row(entry: entry, placement: placement)
            if let index = groups.firstIndex(where: { $0.choice == placement.choice }) {
                groups[index].rows.append(row)
            } else {
                groups.append(Group(choice: placement.choice, option: option(for: placement.choice), rows: [row]))
            }
        }
        // The inbox is the fallback, so it closes the list.
        return groups.filter { $0.choice != .inbox } + groups.filter { $0.choice == .inbox }
    }

    func option(for choice: VoiceDraft.StoreChoice) -> VoiceStoreOption? {
        options.first { $0.choice == choice }
    }

    var selectedCount: Int { draft.selectedCount }

    var targetCount: Int {
        Set(groups.filter { $0.rows.contains(where: \.entry.isSelected) }.map(\.choice)).count
    }

    // MARK: Transcript → draft

    private func receive(_ transcript: LiveTranscriber.Transcript) {
        let finalizedGrew = transcript.finalized.count > self.transcript.finalized.count
        self.transcript = transcript
        applyRules()
        if let name = VoiceRuleParser.lastStoreMention(in: transcript.full, lexicon: lexicon) {
            activeChoice = options.first { $0.name == name }?.choice
        }
        guard usesIntelligence else { return }
        // A finished phrase is read right away; while words still change, wait for a pause.
        modelDebounce?.cancel()
        modelDebounce = Task { [weak self] in
            try? await Task.sleep(for: finalizedGrew ? .milliseconds(150) : .milliseconds(1100))
            guard !Task.isCancelled, let self else { return }
            let text = self.transcript.full
            guard text.count != self.interpretedLength else { return }
            self.modelPass?.cancel()
            self.modelPass = Task { await self.interpret(text) }
        }
    }

    private func receive(level: Float) {
        // Fast attack, slow release – the halo breathes instead of flickering.
        self.level = level > self.level ? level : self.level * 0.82 + level * 0.18
    }

    private func applyRules() {
        let parsed = VoiceRuleParser.parse(transcript.full, lexicon: lexicon, language: language)
        draft.merge(parsed, origin: .rules, transcriptLength: transcript.full.count, isComplete: true)
    }

    private func interpret(_ text: String) async {
        isInterpreting = true
        defer { isInterpreting = false }
        let names = options.map(\.name)
        var latest: [SpokenEntry] = []
        do {
            for try await entries in model.intelligence.interpretDictation(text, stores: names, language: language) {
                try Task.checkCancellation()
                latest = entries
                draft.merge(entries, origin: .model, transcriptLength: text.count, isComplete: false)
            }
            try Task.checkCancellation()
            draft.merge(latest, origin: .model, transcriptLength: text.count, isComplete: true)
            interpretedLength = text.count
        } catch {
            // Cancelled by a newer pass or the model failed: the rules result stays.
        }
    }

    // MARK: Demo

    #if DEBUG
    /// Simulator and screenshots: plays the example dictation word by word.
    private func playDemo() {
        phase = .listening
        let script = language == .english
            ? [
                "I need a dozen eggs and want to get them at the market,", " as well as soup greens and two pounds of potatoes.",
                " At Rewe I want 500 grams of ground beef.", " Oh, and I need onions from the market.",
            ]
            : [
                "Ich brauche 10 Eier und will sie auf dem Markt kaufen,", " genau wie Suppengrün und 500 g Kartoffeln, mehligkochend.",
                " Bei Rewe will ich 500 g Hackfleisch kaufen.", " Ah, und ich brauche Zwiebeln vom Markt.",
            ]
        demo = Task { [weak self] in
            var finalized = ""
            for sentence in script {
                var volatile = ""
                for word in sentence.split(separator: " ") {
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 170...330)))
                    guard !Task.isCancelled, let self else { return }
                    volatile += (volatile.isEmpty ? "" : " ") + word
                    self.receive(LiveTranscriber.Transcript(finalized: finalized, volatile: volatile))
                    self.receive(level: Float.random(in: 0.35...0.95))
                }
                finalized = LiveTranscriber.Transcript.join(finalized, volatile)
                self?.receive(LiveTranscriber.Transcript(finalized: finalized, volatile: ""))
                try? await Task.sleep(for: .milliseconds(450))
                self?.receive(level: 0.05)
            }
            if ProcessInfo.processInfo.arguments.contains("-demo-voice-review") {
                await self?.stop()
            }
        }
    }
    #endif
}
