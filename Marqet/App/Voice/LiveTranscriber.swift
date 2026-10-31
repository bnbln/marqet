@preconcurrency import AVFoundation
import Foundation
import MarqetCore
import Speech

/// Live, on-device transcription of the microphone (KONZEPT §3.3).
///
/// `SpeechAnalyzer` with `SpeechTranscriber` where available, `DictationTranscriber` otherwise.
/// Audio never leaves the device. The user's store names are passed as contextual strings,
/// so "Rewe", "dm" or "Tegut" are recognized as names and not as ordinary words.
@MainActor
final class LiveTranscriber {
    enum Failure: LocalizedError {
        case microphoneDenied
        case unsupportedLanguage
        case noAudioInput

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: String(localized: "Marqet darf das Mikrofon nicht verwenden. Du kannst das in den Einstellungen ändern.")
            case .unsupportedLanguage: String(localized: "Diese Sprache kann auf deinem Gerät nicht transkribiert werden.")
            case .noAudioInput: String(localized: "Es ist kein Mikrofon verfügbar.")
            }
        }
    }

    /// Finalized text plus the still changing (volatile) tail.
    struct Transcript: Equatable {
        var finalized = ""
        var volatile = ""
        /// The user paused before the volatile tail: the finalized text ends its sentence there.
        var volatileFollowsPause = false
        var full: String { Self.join(finalized, volatile, afterPause: volatileFollowsPause) }

        /// Segments arrive without reliable spacing: "kaufen." + "Ah, und" → "kaufen. Ah, und".
        /// After a pause the head ends its sentence: "Brötchen" + "HDMI-Kabel" → "Brötchen. HDMI-Kabel".
        static func join(_ head: String, _ tail: String, afterPause: Bool = false) -> String {
            let tailIsEmpty = tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return PauseMarker.join(afterPause && !tailIsEmpty ? PauseMarker.endingSentence(head) : head, tail)
        }
    }

    private(set) var transcript = Transcript()
    /// Called on every transcript change and with the input level (0…1) about 20× per second.
    var onTranscript: ((Transcript) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var module: (any SpeechModule)?
    /// Audio time at which the last finalized word ended, to find a pause before the next result.
    private var lastFinalizedEnd: Double?
    /// "Weitersprechen": the text heard before ended with the stop button – a pause by definition.
    private var resumesAfterPause: Bool

    init(transcript: Transcript = Transcript()) {
        self.transcript = transcript
        resumesAfterPause = !transcript.full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Preparation

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Picks the transcriber and downloads its language model if needed (`progress` 0…1).
    func prepare(locale preferred: Locale, progress: @escaping @MainActor (Double) -> Void) async throws {
        let module: any SpeechModule
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) {
            // Word timings reveal pauses the transcriber did not punctuate (`PauseMarker`).
            let preset = SpeechTranscriber.Preset.progressiveTranscription
            module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions,
                attributeOptions: preset.attributeOptions.union([.audioTimeRange])
            )
        } else if let locale = await DictationTranscriber.supportedLocale(equivalentTo: preferred) {
            let preset = DictationTranscriber.Preset.progressiveShortDictation
            module = DictationTranscriber(
                locale: locale,
                contentHints: preset.contentHints,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions,
                attributeOptions: preset.attributeOptions.union([.audioTimeRange])
            )
        } else {
            throw Failure.unsupportedLanguage
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let observation = Task { @MainActor in
                while !Task.isCancelled {
                    progress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            defer { observation.cancel() }
            try await request.downloadAndInstall()
        }
        self.module = module
    }

    // MARK: Recording

    func start(contextualStrings: [String]) async throws {
        guard let module else { throw Failure.unsupportedLanguage }
        try await AudioSessionControl.activate()

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0,
              let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: inputFormat)
        else { throw Failure.noAudioInput }

        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try? await analyzer.setContext(context)
        }

        observeResults(of: module)

        let (inputStream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let (levelStream, levels) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.input = input
        try AudioTap.install(on: engine.inputNode, from: inputFormat, to: analyzerFormat, input: input, levels: levels)
        levelTask = Task { [weak self] in
            for await level in levelStream { self?.onLevel?(level) }
        }
        engine.prepare()
        try engine.start()
        try await analyzer.start(inputSequence: inputStream)
    }

    /// Stops listening and waits for the last words to be finalized.
    func finish() async {
        await stopAudio()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        if !transcript.volatile.isEmpty {
            transcript.finalized = transcript.full
            transcript.volatile = ""
            transcript.volatileFollowsPause = false
            onTranscript?(transcript)
        }
        analyzer = nil
    }

    func cancel() async {
        await stopAudio()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        analyzer = nil
    }

    /// Keeps the text heard so far and listens again ("Weitersprechen").
    func resetVolatile() {
        transcript.volatile = ""
        transcript.volatileFollowsPause = false
    }

    private func stopAudio() async {
        // Touching `inputNode` creates the audio unit – only do it if recording ever started.
        guard let input else { return }
        input.finish()
        self.input = nil
        levelTask?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        // Awaited, so "Weitersprechen" cannot activate while this still deactivates.
        await AudioSessionControl.deactivate()
    }

    private func observeResults(of module: any SpeechModule) {
        if let transcriber = module as? SpeechTranscriber {
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.receive(Self.timedRuns(of: result.text), isFinal: result.isFinal)
                    }
                } catch {}
            }
        } else if let transcriber = module as? DictationTranscriber {
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.receive(Self.timedRuns(of: result.text), isFinal: result.isFinal)
                    }
                } catch {}
            }
        }
    }

    /// The result's runs with their audio time ranges, where the transcriber reports them.
    nonisolated private static func timedRuns(of text: AttributedString) -> [TimedText] {
        text.runs.map { run in
            let piece = String(text[run.range].characters)
            guard let range = run.audioTimeRange, range.start.seconds.isFinite, range.end.seconds.isFinite else {
                return TimedText(piece)
            }
            return TimedText(piece, start: range.start.seconds, end: range.end.seconds)
        }
    }

    private func receive(_ runs: [TimedText], isFinal: Bool) {
        let marked = PauseMarker.mark(runs, after: lastFinalizedEnd)
        let afterPause = marked.startsAfterPause || (resumesAfterPause && lastFinalizedEnd == nil)
        if isFinal {
            transcript.finalized = Transcript.join(transcript.finalized, marked.text, afterPause: afterPause)
            transcript.volatile = ""
            transcript.volatileFollowsPause = false
            if let end = marked.lastEnd { lastFinalizedEnd = end }
            if !marked.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { resumesAfterPause = false }
        } else {
            transcript.volatile = marked.text
            transcript.volatileFollowsPause = afterPause
        }
        onTranscript?(transcript)
    }
}

/// Configuring and (de)activating the audio session blocks while the hardware switches – never on
/// the main thread. `nonisolated async` runs on the global executor. The async
/// `activate(options:)` API would need iOS 27; this works from iOS 26.
private enum AudioSessionControl {
    nonisolated static func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    nonisolated static func deactivate() async {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The input tap runs on the audio thread, so it is built outside the main actor.
private enum AudioTap {
    nonisolated static func install(
        on node: AVAudioInputNode,
        from inputFormat: AVAudioFormat,
        to analyzerFormat: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) throws {
        let converter = BufferConverter(from: inputFormat, to: analyzerFormat)
        node.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            levels.yield(Self.level(of: buffer))
            if let converted = converter.convert(buffer) {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    /// RMS mapped to 0…1 on a perceptual (dB) scale.
    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 45, 0), 1)
    }
}

/// Converts microphone buffers to the analyzer's format; used from the audio thread only.
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init(from input: AVAudioFormat, to output: AVAudioFormat) {
        outputFormat = output
        converter = input == output ? nil : AVAudioConverter(from: input, to: output)
        converter?.primeMethod = .none
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}
