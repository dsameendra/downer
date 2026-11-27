//
//  CleanupAndPlacementTests.swift
//  DownerTests
//
//  2.2.1: cancel cleanup, playlist folders, window placement.
//

import Foundation
import Testing
@testable import Downer

struct PartialFilesTests {
    @Test func recognisesUnfinishedPiecesOnly() {
        for rest in [".mp4.part", ".webm.ytdl", ".mp4.part-Frag12", ".f137.mp4", ".f137.mp4.part", ".f251.webm.ytdl",
                     ".temp.mp4", ".f137.mp4.part-Frag3.part"] {
            #expect(PartialFiles.isPiece(rest), "\(rest)")
        }
        for rest in [".mp4", ".mkv", ".opus", ".jpg", ".en.vtt", " copy.mp4"] {
            #expect(!PartialFiles.isPiece(rest), "\(rest)")
        }
    }

    private func scratch() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pf-\(UUID())")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func removesLeftoversKeepsEverythingElse() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        func make(_ name: String, age: TimeInterval = 0) throws {
            let u = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: u)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
        }
        let started = Date().addingTimeInterval(-5)
        try make("A [1].f137.mp4.part"); try make("A [1].f251.webm"); try make("A [1].mp4.ytdl")
        try make("A [1].mp4")                      // a finished video of the same name: kept
        try make("B [2].mp4.part", age: 3600)      // older than this run: not ours
        try make("notes.txt"); try make("A.mp4.part")  // unrelated
        PartialFiles.clean(after: [dir.appendingPathComponent("A [1].mp4")], destination: dir, since: started)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(left == ["A [1].mp4", "B [2].mp4.part", "notes.txt", "A.mp4.part"])
    }

    @Test func removesAnEmptiedPlaylistFolderButNeverTheDestination() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("My List")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("A [1].mp4.part"))
        PartialFiles.clean(after: [folder.appendingPathComponent("A [1].mp4")], destination: dir, since: Date().addingTimeInterval(-5))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: dir.path))
        // a folder that still holds a finished video stays
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("Done [0].mp4"))
        PartialFiles.clean(after: [folder.appendingPathComponent("A [1].mp4")], destination: dir, since: .distantPast)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Done [0].mp4").path))
    }
}

struct PlaylistFolderArgumentTests {
    func templates(folder: Bool) -> [String] {
        let o = JobOptions(
            type: .both, resolution: "1080", container: "mp4", audioQuality: "source", audioFormat: "opus",
            folder: URL(fileURLWithPath: "/Users/x/Downloads"))
        let args = YtDlpArguments.build(
            for: o,
            purpose: .download(pathFile: "/p", ffmpegDirectory: "/f", outputFolder: "/Users/x/Downloads", only: nil, startedFile: "/s", playlistFolder: folder),
            useCookies: false, url: "https://example.com/v")
        #expect(args.contains("before_dl:filename"))
        return args.indices.filter { args[$0] == "-o" }.map { args[$0 + 1] }
    }

    @Test func folderOnlyWhenTheSettingIsOn() {
        #expect(templates(folder: true)[0] == "/Users/x/Downloads/%(playlist_title)s/%(title)s [%(id)s].%(ext)s")
        #expect(templates(folder: false)[0] == "/Users/x/Downloads/%(title)s [%(id)s].%(ext)s")
    }
}

struct WindowPlacementTests {
    let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
    @Test func reachability() {
        #expect(WindowPlacement.isReachable(NSRect(x: 100, y: 100, width: 400, height: 540), screens: screens))
        #expect(!WindowPlacement.isReachable(NSRect(x: 3000, y: 100, width: 400, height: 540), screens: screens))
        #expect(!WindowPlacement.isReachable(NSRect(x: 1400, y: 100, width: 400, height: 540), screens: screens))
        #expect(WindowPlacement.isReachable(NSRect(x: 3000, y: 100, width: 400, height: 540),
                                            screens: screens + [NSRect(x: 2560, y: 0, width: 1920, height: 1080)]))
    }
}
