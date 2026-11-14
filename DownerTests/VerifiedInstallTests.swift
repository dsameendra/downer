//
//  VerifiedInstallTests.swift
//  DownerTests
//
//  Checksums for downloaded tools, and replacing a binary in one step.
//

import CryptoKit
import Foundation
import Testing

@testable import Downer

struct VerifiedInstallTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("downer-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func sha256MatchesTheKnownDigest() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("f")
        try Data("abc".utf8).write(to: file)
        #expect(
            try DependencyManager.sha256Hex(of: file)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func readsTheHashForTheRightAsset() {
        let a = String(repeating: "a", count: 64), b = String(repeating: "B", count: 64)
        let sums = "\(a)  yt-dlp\n\(b)  yt-dlp_macos\n\(a) *yt-dlp_linux\n"
        #expect(DependencyManager.expectedHash(in: sums, for: "yt-dlp_macos") == b.lowercased())
        #expect(DependencyManager.expectedHash(in: sums, for: "yt-dlp_linux") == a)
        #expect(DependencyManager.expectedHash(in: sums, for: "yt-dlp_macos_legacy") == nil)
        #expect(DependencyManager.expectedHash(in: "", for: "x") == nil)
        #expect(DependencyManager.expectedHash(in: "not-a-hash  yt-dlp_macos", for: "yt-dlp_macos") == nil)
    }

    @Test func bareHashesOnlyCountWhenAllowed() {
        let a = String(repeating: "c", count: 64)
        #expect(DependencyManager.expectedHash(in: a + "\n", for: "deno.zip") == nil)
        #expect(DependencyManager.expectedHash(in: a + "\n", for: "deno.zip", allowBare: true) == a)
        #expect(DependencyManager.expectedHash(in: a + "  deno.zip\n", for: "deno.zip") == a)
    }

    @Test func installReplacesInPlaceAndKeepsPermissions() throws {
        let fm = FileManager.default
        let dir = try scratch()
        defer { try? fm.removeItem(at: dir) }
        let bin = dir.appendingPathComponent("bin")
        let dest = bin.appendingPathComponent("yt-dlp")

        let first = dir.appendingPathComponent("one")
        try Data("old".utf8).write(to: first)
        try DependencyManager.installAtomically(first, to: dest)  // creates the folder, no old file
        #expect(try String(contentsOf: dest, encoding: .utf8) == "old")
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)  // an old file that is not executable

        let second = dir.appendingPathComponent("two")
        try Data("new".utf8).write(to: second)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: second.path)
        try DependencyManager.installAtomically(second, to: dest)
        #expect(try String(contentsOf: dest, encoding: .utf8) == "new")
        let mode = try fm.attributesOfItem(atPath: dest.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o755)
        #expect(try fm.contentsOfDirectory(atPath: bin.path) == ["yt-dlp"])  // no staging file left behind
    }
}
