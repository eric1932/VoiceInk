import Foundation

/// Remembers the last text seen in the observed field. Chat apps clear the field
/// when a message is sent, so the final read alone would lose the user's edit.
struct AutoLearnFieldSampler {
    enum Event: Equatable {
        case none
        /// The field was emptied, stopped being readable, or its text was replaced
        /// wholesale (a message was sent and a new one started between two reads).
        case cleared
    }

    private(set) var lastText: String?
    private var lastTextIsStable = false
    private var consecutiveUnreadable = 0

    /// The last text, once two reads in a row agreed on it. Text that was still
    /// changing (a half-typed word, an IME composition) is not trusted.
    var settledText: String? { lastTextIsStable ? lastText : nil }

    /// Records one read of the field. `text` is nil when the read failed.
    mutating func record(_ text: String?) -> Event {
        guard let text else {
            consecutiveUnreadable += 1
            return consecutiveUnreadable >= 2 && lastText != nil ? .cleared : .none
        }
        consecutiveUnreadable = 0
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return lastText != nil ? .cleared : .none
        }
        if let previous = lastText, Self.isReplacement(of: previous, by: text) {
            return .cleared
        }
        lastTextIsStable = text == lastText
        lastText = text
        return .none
    }

    /// Editing changes a field a little between two reads, so the reads still share
    /// a beginning or an end. Sharing at most one character means the text was replaced.
    private static func isReplacement(of previous: String, by text: String) -> Bool {
        guard previous.count >= 4 else { return false }
        let sharedPrefix = zip(previous, text).prefix { $0 == $1 }.count
        let sharedSuffix = zip(previous.reversed(), text.reversed()).prefix { $0 == $1 }.count
        return sharedPrefix + sharedSuffix <= 1
    }
}
