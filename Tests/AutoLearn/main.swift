import Foundation

var passed = 0

func check(_ name: String, _ condition: Bool) {
    guard condition else {
        print("FAIL: \(name)")
        exit(1)
    }
    passed += 1
}

/// Runs a paste/edit through the same steps Auto-Learn uses and returns the rules
/// the local reviewer would suggest, as "source→destination".
func learned(field: String, pasted: String, final: String) -> [String] {
    let range = (field as NSString).range(of: pasted)
    let snapshot = AutoLearnFieldSnapshot(
        baselineFieldText: field, finalFieldText: final,
        pastedRange: range, originalPastedText: pasted)
    guard let revision = FinalSnapshotDiffEngine.revision(from: snapshot) else { return [] }
    return CorrectionDiffEngine.candidates(from: revision, usesAIReviewer: false).compactMap { candidate in
        guard let pair = CorrectionDiffEngine.replacementPair(
                from: .init(original: candidate.originalText, corrected: candidate.correctedText)),
            AutoLearnLocalReviewPolicy.accepts(source: pair.source, destination: pair.destination)
        else { return nil }
        return "\(pair.source)→\(pair.destination)"
    }
}

// MARK: - Existing English behavior

check("en_wordFix", learned(field: "I think voice ink works.", pasted: "I think voice ink works.",
    final: "I think VoiceInk works.") == ["voice ink→VoiceInk"])
check("en_pluralIgnored", learned(field: "I like the model.", pasted: "I like the model.",
    final: "I like the models.") == [])

print("Auto-Learn tests: \(passed) passed")
