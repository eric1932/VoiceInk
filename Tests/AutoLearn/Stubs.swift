import Foundation

// Stand-ins for app types the tested files reference but the tests do not exercise.
enum AutoLearnSettings {
    static var usesAIReviewer = false
}

enum AutoLearnReviewEligibility {
    static func accepts(source: String?, destination: String, aiReviewConfigurationID: String?) -> Bool {
        true
    }
}
