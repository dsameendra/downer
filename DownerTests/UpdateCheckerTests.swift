//
//  UpdateCheckerTests.swift
//  DownerTests
//
//  The pieces of the Sparkle integration that don't need Sparkle running: moving the old Settings
//  switch across, and deciding whether the build carries a real public key.
//

import Foundation
import Testing
@testable import Downer

struct UpdateCheckerTests {
    /// A throwaway defaults domain so the tests never touch the real preferences.
    private func freshDefaults() -> UserDefaults {
        let name = "UpdateCheckerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func migrationWithNoOldSettingReturnsNil() {
        #expect(UpdateChecker.migrate(defaults: freshDefaults()) == nil)
    }

    @Test func migrationCarriesTheOldSwitchAcross() {
        let on = freshDefaults()
        on.set(true, forKey: "autoCheckUpdates")
        #expect(UpdateChecker.migrate(defaults: on) == true)

        let off = freshDefaults()
        off.set(false, forKey: "autoCheckUpdates")
        #expect(UpdateChecker.migrate(defaults: off) == false)
    }

    @Test func migrationRemovesTheLegacyKeys() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "autoCheckUpdates")
        defaults.set(Date(), forKey: "lastUpdateCheck")
        _ = UpdateChecker.migrate(defaults: defaults)
        #expect(defaults.object(forKey: "autoCheckUpdates") == nil)
        #expect(defaults.object(forKey: "lastUpdateCheck") == nil)
        // a second run finds nothing, so a later change in Sparkle's own setting is never overwritten
        #expect(UpdateChecker.migrate(defaults: defaults) == nil)
    }

    @Test func publicKeyConfiguration() {
        #expect(!UpdateChecker.isConfigured(key: nil))
        #expect(!UpdateChecker.isConfigured(key: ""))
        #expect(!UpdateChecker.isConfigured(key: "   \n"))
        #expect(!UpdateChecker.isConfigured(key: UpdateChecker.placeholderKey))
        #expect(!UpdateChecker.isConfigured(key: " \(UpdateChecker.placeholderKey)\n"))
        #expect(UpdateChecker.isConfigured(key: "vVlIGQyW+5kk5XqoRwEIWT7dXlQ1E3Xx0GJ1d7GFHcY="))
    }
}
