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

    /// Tests run in parallel, so each gets its own defaults domain.
    func freshDefaults() -> (UserDefaults, String) {
        let name = "JsRuntimeGateTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// Queued links don't fix the flag when they are added; it is decided for the yt-dlp that runs.
    @Test func addingALinkDoesNotDecideTheRuntime() {
        let (suite, name) = freshDefaults()
        defer { suite.removePersistentDomain(forName: name) }
        DependencyManager.cacheYtDlpVersion("2026.08.19", path: "/opt/homebrew/bin/yt-dlp", defaults: suite)
        #expect(JobOptions.current(suite).jsRuntimePath == nil)
    }

    @Test func runtimeFollowsTheYtDlpThatRuns() {
        let (suite, name) = freshDefaults()
        defer { suite.removePersistentDomain(forName: name) }
        let deno = { Optional("/opt/homebrew/bin/deno") }
        let brew = "/opt/homebrew/bin/yt-dlp"
        DependencyManager.cacheYtDlpVersion("2026.08.19", path: brew, defaults: suite)
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: brew, defaults: suite, deno: deno) == "/opt/homebrew/bin/deno")

        // Browse… picked an older copy: until its version is known, and once it is, no flag
        let old = "/Users/x/bin/yt-dlp"
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: old, defaults: suite, deno: deno) == nil)
        DependencyManager.cacheYtDlpVersion("2025.10.22", path: old, defaults: suite)
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: old, defaults: suite, deno: deno) == nil)
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: brew, defaults: suite, deno: deno) == nil)
    }

    /// Downer 2.1.0 builds before this saved the version without its path; trust it until the next refresh.
    @Test func aVersionSavedWithoutItsPathIsTrusted() {
        let (suite, name) = freshDefaults()
        defer { suite.removePersistentDomain(forName: name) }
        suite.set("2026.08.19", forKey: DependencyManager.ytDlpVersionKey)
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: "/any/yt-dlp", defaults: suite, deno: { "/d" }) == "/d")
        suite.set("2025.10.22", forKey: DependencyManager.ytDlpVersionKey)
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: "/any/yt-dlp", defaults: suite, deno: { "/d" }) == nil)
    }

    @Test func noDenoOrNoVersionMeansNoRuntime() {
        let (suite, name) = freshDefaults()
        defer { suite.removePersistentDomain(forName: name) }
        let path = "/opt/homebrew/bin/yt-dlp"
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: path, defaults: suite, deno: { "/d" }) == nil)
        DependencyManager.cacheYtDlpVersion("2026.08.19", path: path, defaults: suite)
        #expect(DependencyManager.jsRuntimePath(forYtDlpAt: path, defaults: suite, deno: { nil }) == nil)
        // a refresh that found no yt-dlp clears both values
        DependencyManager.cacheYtDlpVersion(nil, path: nil, defaults: suite)
        #expect(suite.string(forKey: DependencyManager.ytDlpVersionKey) == nil)
        #expect(suite.string(forKey: DependencyManager.ytDlpVersionPathKey) == nil)
    }
}
