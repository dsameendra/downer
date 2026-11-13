//
//  ToolUpdateTests.swift
//  DownerTests
//
//  Which way each tool is updated, and how deno reaches yt-dlp.
//

import Foundation
import Testing
@testable import Downer

struct ToolUpdateTests {
    let managed = "/Users/x/Library/Application Support/Downer/bin"

    func method(_ tool: Tool, _ path: String) -> UpdateMethod {
        DependencyManager.updateMethod(for: tool, resolvedPath: path, managedDir: managed)
    }

    @Test func homebrewPathsUpgradeThroughBrew() {
        #expect(method(.ytDlp, "/opt/homebrew/bin/yt-dlp") == .brew(formula: "yt-dlp"))
        #expect(method(.ytDlp, "/usr/local/Cellar/yt-dlp/2025.1.1/bin/yt-dlp") == .brew(formula: "yt-dlp"))
        #expect(method(.deno, "/opt/homebrew/Cellar/deno/2.1.4/bin/deno") == .brew(formula: "deno"))
    }

    @Test func ffmpegAndFfprobeShareAFormula() {
        #expect(method(.ffmpeg, "/opt/homebrew/bin/ffmpeg") == .brew(formula: "ffmpeg"))
        #expect(method(.ffprobe, "/opt/homebrew/bin/ffprobe") == .brew(formula: "ffmpeg"))
    }

    @Test func managedBinariesUpdateThemselves() {
        #expect(method(.ytDlp, managed + "/yt-dlp") == .selfUpdate(args: ["-U"]))
        #expect(method(.deno, managed + "/deno") == .selfUpdate(args: ["upgrade"]))
        #expect(method(.ffmpeg, managed + "/ffmpeg") == .manual)
    }

    @Test func otherPathsAreManual() {
        #expect(method(.ytDlp, "/Users/x/bin/yt-dlp") == .manual)
        #expect(method(.deno, "/Users/x/.deno/bin/deno") == .manual)
        #expect(method(.ytDlp, "/usr/local/bin/yt-dlp") == .manual)  // unresolved: not known to be brew
        #expect(method(.ytDlp, managed + "-other/yt-dlp") == .manual)
    }

    @Test func denoIsRecommendedNotRequired() {
        #expect(!Tool.deno.isRequired)
        #expect(Tool.ytDlp.isRequired && Tool.ffmpeg.isRequired && Tool.ffprobe.isRequired)
        #expect(Tool.deno.installGroup == .deno)
        #expect(Tool.ffprobe.installGroup == .ffmpeg)
    }

    func options(js: String?) -> JobOptions {
        JobOptions(
            type: .both, resolution: "1080", container: "mp4", audioQuality: "source",
            audioFormat: "opus", folder: URL(fileURLWithPath: "/tmp"), jsRuntimePath: js)
    }

    @Test func jsRuntimeIsPassedToProbeAndDownload() {
        let o = options(js: "/opt/homebrew/bin/deno")
        let probe = YtDlpArguments.build(for: o, purpose: .probe(only: nil), useCookies: false, url: "u")
        let dl = YtDlpArguments.build(
            for: o, purpose: .download(pathFile: "/p", ffmpegDirectory: "/f", only: nil),
            useCookies: false, url: "u")
        for args in [probe, dl] {
            let i = args.firstIndex(of: "--js-runtimes")
            #expect(i != nil)
            #expect(args[i! + 1] == "deno:/opt/homebrew/bin/deno")
            #expect(args.last == "u")
        }
    }

    @Test func noRuntimeMeansNoFlag() {
        let args = YtDlpArguments.build(
            for: options(js: nil), purpose: .probe(only: nil), useCookies: false, url: "u")
        #expect(!args.contains("--js-runtimes"))
    }
}
