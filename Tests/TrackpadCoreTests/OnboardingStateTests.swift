import Foundation
import XCTest
@testable import TrackpadCore

final class OnboardingStateTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) throws {
        let suite = "Numpad.OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testFreshInstallShowsGuideThenCompletionSuppressesIt() throws {
        try withDefaults { defaults in
            XCTAssertTrue(OnboardingState.shouldPresent(arguments: [], defaults: defaults))
            OnboardingState.complete(defaults: defaults)
            XCTAssertFalse(OnboardingState.shouldPresent(arguments: [], defaults: defaults))
        }
    }

    func testDeletingCompletionPreferenceMakesTheGuideShowAgain() throws {
        try withDefaults { defaults in
            OnboardingState.complete(defaults: defaults)
            defaults.removeObject(forKey: OnboardingState.completionKey)
            XCTAssertTrue(OnboardingState.shouldPresent(arguments: [], defaults: defaults))
        }
    }

    func testExplicitGuideCanBeOpenedAfterCompletion() throws {
        try withDefaults { defaults in
            OnboardingState.complete(defaults: defaults)
            XCTAssertTrue(OnboardingState.shouldPresent(arguments: ["--onboarding"], defaults: defaults))
        }
    }

    func testSettingsAndSmokeTestDoNotOpenTwoWindowsOnFirstLaunch() throws {
        try withDefaults { defaults in
            for argument in ["--settings", "--smoke-test"] {
                XCTAssertFalse(OnboardingState.shouldPresent(arguments: [argument], defaults: defaults))
                XCTAssertTrue(OnboardingState.shouldPresent(arguments: [argument, "--onboarding"], defaults: defaults))
            }
        }
    }
}
