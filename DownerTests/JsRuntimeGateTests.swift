//
//  JsRuntimeGateTests.swift
//  DownerTests
//

import Foundation
import Testing
@testable import Downer

struct JsRuntimeGateTests {
    @Test func olderVersionsAreRefused() {
        #expect(!DependencyManager.supportsJsRuntimes("2025.10.22"))
        #expect(!DependencyManager.supportsJsRuntimes("2025.11.11"))
        #expect(!DependencyManager.supportsJsRuntimes("2024.12.30"))
        #expect(!DependencyManager.supportsJsRuntimes("2025.09.26"))
    }

    @Test func supportingVersionsAreAccepted() {
        #expect(DependencyManager.supportsJsRuntimes("2025.11.12"))
        #expect(DependencyManager.supportsJsRuntimes("2025.11.13"))
        #expect(DependencyManager.supportsJsRuntimes("2025.12.01"))
        #expect(DependencyManager.supportsJsRuntimes("2026.08.19"))
        #expect(DependencyManager.supportsJsRuntimes("2025.11.12.232815"))
        #expect(DependencyManager.supportsJsRuntimes(" 2026.01.02 "))
    }

    @Test func unknownVersionsAreRefused() {
        #expect(!DependencyManager.supportsJsRuntimes(nil))
        #expect(!DependencyManager.supportsJsRuntimes(""))
        #expect(!DependencyManager.supportsJsRuntimes("garbage"))
        #expect(!DependencyManager.supportsJsRuntimes("2026.08"))
    }

    @Test func currentOptionsHonourCachedVersion() {
        let suite = UserDefaults(suiteName: "JsRuntimeGateTests")!
        suite.removePersistentDomain(forName: "JsRuntimeGateTests")
        #expect(JobOptions.current(suite).jsRuntimePath == nil)
        suite.set("2025.10.22", forKey: "ytDlpVersion")
        #expect(JobOptions.current(suite).jsRuntimePath == nil)
        suite.removePersistentDomain(forName: "JsRuntimeGateTests")
    }
}
