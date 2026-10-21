import Foundation

public enum OnboardingState {
    public static let completionKey = "onboardingCompleted"

    public static func shouldPresent(arguments: [String], defaults: UserDefaults = .standard) -> Bool {
        if arguments.contains("--onboarding") { return true }
        if arguments.contains("--settings") || arguments.contains("--smoke-test") { return false }
        return !defaults.bool(forKey: completionKey)
    }

    public static func complete(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completionKey)
    }
}
