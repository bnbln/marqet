import Foundation

/// A piece of transcribed text with the audio time it was spoken at (seconds since the start of
/// the recording). Spaces and punctuation usually come without a time.
public struct TimedText: Hashable, Sendable {
    public var text: String
    public var start: Double?
    public var end: Double?

    public init(_ text: String, start: Double? = nil, end: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Ends a sentence where the speaker paused.
///
/// The on-device transcriber often writes "Brötchen HDMI-Kabel beim Mediamarkt" even though the
/// user paused after "Brötchen". A pause separates two thoughts, so `VoiceRuleParser` must see it:
/// a period there keeps "beim Mediamarkt" with the HDMI cable instead of the bread rolls.
public enum PauseMarker {
    /// Silence between two words that counts as a pause. Words of one enumeration ("Milch, Butter,
    /// Eier") follow each other faster; a deliberate pause is longer.
    public static let threshold: Double = 0.8

    public struct Marked: Hashable, Sendable {
        /// The text with a period at every pause.
        public var text: String
        /// The pause came before the first word – the text before it should end its sentence.
        public var startsAfterPause: Bool
        /// End time of the last timed word.
        public var lastEnd: Double?
    }

    /// Joins `runs`, ending the sentence at every pause of at least `threshold` seconds.
    /// - Parameter previousEnd: end time of the word heard before `runs`, to find a pause before them.
    public static func mark(_ runs: [TimedText], after previousEnd: Double?, threshold: Double = threshold) -> Marked {
        var text = ""
        var startsAfterPause = false
        var lastEnd = previousEnd
        for run in runs {
            if let start = run.start, let end = lastEnd, start - end >= threshold,
               !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startsAfterPause = true
                } else {
                    // `endingSentence` drops the trailing space, `join` puts one back.
                    text = join(endingSentence(text), run.text)
                    if let end = run.end { lastEnd = max(end, lastEnd ?? end) }
                    continue
                }
            }
            // Runs of one result carry their own spacing ("HDMI" "-" "Kabel").
            text += run.text
            if let end = run.end { lastEnd = max(end, lastEnd ?? end) }
        }
        return Marked(text: text, startsAfterPause: startsAfterPause, lastEnd: lastEnd)
    }

    /// "Brötchen" → "Brötchen.", "Brötchen," → "Brötchen."; a sentence that already ends stays.
    public static func endingSentence(_ text: String) -> String {
        var trimmed = text
        while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
        guard let last = trimmed.last else { return text }
        if ".!?;:".contains(last) { return trimmed }
        if last == "," { trimmed.removeLast() }
        return trimmed + "."
    }

    /// Segments arrive without reliable spacing: "kaufen." + "Ah, und" → "kaufen. Ah, und".
    public static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        if last.isWhitespace || first.isWhitespace || ".,!?;:".contains(first) { return head + tail }
        return head + " " + tail
    }
}
