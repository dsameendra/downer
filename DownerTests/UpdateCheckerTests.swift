import Testing

@testable import Downer

struct UpdateCheckerTests {
    @Test func numericNotLexicographic() {
        #expect(UpdateChecker.isNewer("2.10.0", than: "2.9.1"))
        #expect(!UpdateChecker.isNewer("2.9.1", than: "2.10.0"))
    }

    @Test func missingComponentsAreZero() {
        #expect(!UpdateChecker.isNewer("2.1", than: "2.1.0"))
        #expect(!UpdateChecker.isNewer("2.1.0", than: "2.1"))
        #expect(UpdateChecker.isNewer("2.1.1", than: "2.1"))
    }

    @Test func equalAndOlder() {
        #expect(!UpdateChecker.isNewer("2.0.3", than: "2.0.3"))
        #expect(!UpdateChecker.isNewer("2.0.2", than: "2.0.3"))
        #expect(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }

    @Test func suffixesAndPrefixesAreIgnored() {
        #expect(!UpdateChecker.isNewer("2.1.0-beta.1", than: "2.1.0"))
        #expect(UpdateChecker.isNewer("2.1.1-rc1", than: "2.1.0"))
        #expect(UpdateChecker.isNewer("v2.1.0", than: "2.0.3"))
    }
}
