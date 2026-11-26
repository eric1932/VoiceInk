import Foundation

/// Remembers the last text seen in the observed field. Chat apps clear the field
/// when a message is sent, so the final read alone would lose the user's edit.
struct AutoLearnFieldSampler {
    enum Event: Equatable {
        case none
        /// The field was emptied or stopped being readable after holding text.
        case cleared
    }

    private(set) var lastText: String?
    private var consecutiveUnreadable = 0

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
        lastText = text
        return .none
    }
}
