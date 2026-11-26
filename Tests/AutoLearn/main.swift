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

// MARK: - Chinese and mixed Chinese/English learn words, not whole clauses

let s1 = "今天安排差啥没干，6点半去Kupertino杨国福吃饭。"
check("cjk_mixedLatinWord", learned(field: s1, pasted: s1,
    final: s1.replacingOccurrences(of: "Kupertino", with: "Cupertino")) == ["Kupertino→Cupertino"])
let s2 = "我们明天去北鲸开会，然后顺便吃个饭。"
check("cjk_wordFix", learned(field: s2, pasted: s2,
    final: s2.replacingOccurrences(of: "北鲸", with: "北京")) == ["北鲸→北京"])
let s3 = "我觉得这个功能在大多数情况下都挺好用的但是有时候它根本就没有触发我也不知道为什么会这样"
check("cjk_longSentence_learnsWordOnly", learned(field: s3, pasted: s3,
    final: s3.replacingOccurrences(of: "触发", with: "出发")) == ["触发→出发"])
let s4 = "那那个Waveform CLI是什么呢？"
check("cjk_latinNextToHan", learned(field: s4, pasted: s4,
    final: "那那个 vphone CLI是什么呢？") == ["Waveform→vphone"])
let s5 = "他高兴的跳了起来"
check("cjk_singleCharNotLearned", learned(field: s5, pasted: s5,
    final: "他高兴地跳了起来") == [])

print("Auto-Learn tests: \(passed) passed")
